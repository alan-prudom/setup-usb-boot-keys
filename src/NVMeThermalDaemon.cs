using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;

namespace NVMeThermal
{
    public class Daemon
    {
        // P/Invoke for Direct Win32 Power Scheme Manipulation (Zero Child Process Overhead)
        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerWriteACValueIndex(
            IntPtr RootPowerKey,
            ref Guid SchemeGuid,
            ref Guid SubGroupOfPowerSettingsGuid,
            ref Guid PowerSettingGuid,
            uint AcValueIndex
        );

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerSetActiveScheme(
            IntPtr UserRootPowerKey,
            ref Guid SchemeGuid
        );

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerGetActiveScheme(
            IntPtr UserRootPowerKey,
            out IntPtr ActivePolicyGuid
        );

        // Power Setting GUIDs
        private static Guid GUID_PROCESSOR_SETTINGS_SUBGROUP = new Guid("54533251-82be-4824-96c1-47b60b740d00");
        private static Guid GUID_PROCTHROTTLEMAX = new Guid("bc5038f7-23e0-4960-96da-33abaf5935ec");

        // Paths
        private const string STATE_FILE = @"D:\nvme_state.json";
        private const string CONTROL_FILE = @"D:\nvme_control.json";
        private const string LOG_DIR = @"D:\logs";

        // Configuration
        private static int maxCpuCeiling = 75; // Default 75%
        private const int SAFE_FLOOR_TEMP = 50;
        private const int SUSTAINED_TEMP_LOW = 51;
        private const int SUSTAINED_TEMP_HIGH = 54;
        private const int ACTIVE_STEP_TEMP = 55;
        private const int DEEP_COOL_TEMP = 57;
        private const int CRITICAL_TEMP = 59;
        private const int CHASSIS_PREDICTIVE_LIMIT = 38;

        // Enhanced Recovery Dwell Configuration
        private const int STANDARD_DWELL_SEC = 30;
        private const int COLD_SOAK_DWELL_SEC = 120; // 120s cold soak after emergency clamp

        // Runtime State
        private static int currentCpuLimit = -1;
        private static int lastLoggedCpu = -1;
        private static int lastLoggedTemp = -1;
        private static int dwellTimer = 0;
        private static int probePenaltyTimer = 0;
        private static bool inEmergencyCooldown = false;
        private static Guid activeSchemeGuid;

        public static void Main(string[] args)
        {
            Console.WriteLine("==========================================================");
            Console.WriteLine("  Dual-Sensor Predictive NVMe Thermal Governor (v2.1)    ");
            Console.WriteLine("  [Gentle Multi-Step Recovery & Cold-Soak Damping Engine] ");
            Console.WriteLine("==========================================================");

            int customMax;
            if (args.Length > 0 && int.TryParse(args[0], out customMax))
            {
                if (customMax >= 50 && customMax <= 100) maxCpuCeiling = customMax;
            }

            Console.WriteLine("  Max CPU Ceiling  : " + maxCpuCeiling + "%");
            Console.WriteLine("  Sensors Monitored: Samsung NVMe Die + Chassis ACPI Zone");
            Console.WriteLine("  Recovery Mode    : Gentle +5% Multi-Step with 120s Cold Soak");
            Console.WriteLine("  State Output     : " + STATE_FILE);
            Console.WriteLine("  Log Directory    : " + LOG_DIR);
            Console.WriteLine("----------------------------------------------------------");

            if (!Directory.Exists(LOG_DIR))
            {
                try { Directory.CreateDirectory(LOG_DIR); } catch { }
            }

            // Obtain active power scheme
            IntPtr schemePtr;
            if (PowerGetActiveScheme(IntPtr.Zero, out schemePtr) == 0)
            {
                activeSchemeGuid = (Guid)Marshal.PtrToStructure(schemePtr, typeof(Guid));
            }
            else
            {
                activeSchemeGuid = new Guid("381b4222-f694-41f0-9685-ff5bb260df2e"); // Balanced fallback
            }

            // Initialize Power
            SetCpuPowerLimit(70);

            // Housekeeping: Purge logs older than 7 days
            PurgeOldLogs();

            // Main Control Loop
            while (true)
            {
                try
                {
                    CheckControlOverrides();

                    int nvmeTemp = GetNvmeDieTemperature();
                    int chassisTemp = GetChassisAcpiTemperature();
                    int thermalDelta = (nvmeTemp > 0 && chassisTemp > 0) ? (nvmeTemp - chassisTemp) : 0;

                    if (nvmeTemp <= 0)
                    {
                        Console.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss") + "] [WARN] NVMe temp read failed. Retrying in 4s...");
                        Thread.Sleep(4000);
                        continue;
                    }

                    int pollInterval = ProcessThermalLadder(nvmeTemp, chassisTemp, thermalDelta);
                    Thread.Sleep(pollInterval * 1000);
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[ERROR] Governor Loop Exception: " + ex.Message);
                    Thread.Sleep(4000);
                }
            }
        }

        private static int ProcessThermalLadder(int nvmeTemp, int chassisTemp, int deltaT)
        {
            int targetCpu = currentCpuLimit;
            int pollSec = 4;
            string stateTag = "NORMAL";
            string statusDesc = "Stable";

            // Decrement penalty timer
            if (probePenaltyTimer > 0)
            {
                probePenaltyTimer = Math.Max(0, probePenaltyTimer - 4);
            }

            // Thermal Control Matrix
            if (nvmeTemp >= CRITICAL_TEMP) // >= 59C
            {
                targetCpu = 40;
                dwellTimer = 0;
                probePenaltyTimer = 120; // Enforce 2-minute penalty
                inEmergencyCooldown = true;
                pollSec = 1;
                stateTag = "CRITICAL 40%";
                statusDesc = "Emergency Clamping (1s poll)";
            }
            else if (nvmeTemp >= DEEP_COOL_TEMP) // 57C - 58C
            {
                targetCpu = 40;
                dwellTimer = 0;
                probePenaltyTimer = 90;
                inEmergencyCooldown = true;
                pollSec = 2;
                stateTag = "DEEP COOL 40%";
                statusDesc = "Deep Cooling Step-Down";
            }
            else if (nvmeTemp >= ACTIVE_STEP_TEMP) // 55C - 56C
            {
                targetCpu = Math.Min(currentCpuLimit, 50); // Drop to 50%
                dwellTimer = 0;
                probePenaltyTimer = 60;
                inEmergencyCooldown = true;
                pollSec = 3;
                stateTag = "ACTIVE 50%";
                statusDesc = "Active Heat Safeguard";
            }
            else if (nvmeTemp >= SUSTAINED_TEMP_LOW && nvmeTemp <= SUSTAINED_TEMP_HIGH) // 51C - 54C
            {
                // In sustained zone, hold current safe floor
                if (inEmergencyCooldown)
                {
                    // Gentle step-up recovery: don't exceed 60% while still in sustained zone
                    targetCpu = Math.Min(currentCpuLimit, 60);
                }
                else
                {
                    targetCpu = Math.Min(currentCpuLimit, 70);
                }
                dwellTimer = 0;
                pollSec = 4;
                stateTag = "SUSTAINED " + targetCpu + "%";
                statusDesc = "Sustained Safe Limit";
            }
            else // <= 50C (OPTIMAL ZONE)
            {
                pollSec = 4;
                int requiredDwell = inEmergencyCooldown ? COLD_SOAK_DWELL_SEC : STANDARD_DWELL_SEC;

                if (probePenaltyTimer > 0)
                {
                    statusDesc = "Cooldown Penalty (" + probePenaltyTimer + "s rem)";
                    stateTag = "COOLDOWN " + currentCpuLimit + "%";
                }
                else if (chassisTemp >= CHASSIS_PREDICTIVE_LIMIT)
                {
                    statusDesc = "Predictive Hold (Chassis >= " + CHASSIS_PREDICTIVE_LIMIT + "C)";
                    stateTag = "PREDICTIVE " + currentCpuLimit + "%";
                }
                else
                {
                    dwellTimer += 4;
                    if (dwellTimer >= requiredDwell)
                    {
                        dwellTimer = 0;
                        if (currentCpuLimit < maxCpuCeiling)
                        {
                            // Gentle Multi-Step Probe: +5% micro-step
                            targetCpu = Math.Min(maxCpuCeiling, currentCpuLimit + 5);
                            statusDesc = "Gentle Probe (+5% -> " + targetCpu + "%)";
                            
                            // Clear emergency cooldown once we successfully reach 65%
                            if (targetCpu >= 65) inEmergencyCooldown = false;
                        }
                        else
                        {
                            statusDesc = "Ceiling Sustained";
                            inEmergencyCooldown = false;
                        }
                    }
                    else
                    {
                        statusDesc = inEmergencyCooldown ? "Cold-Soak Dwell (" + (requiredDwell - dwellTimer) + "s rem)" : "Stable Dwell (" + (requiredDwell - dwellTimer) + "s rem)";
                    }
                    stateTag = "OPTIMAL " + currentCpuLimit + "%";
                }
            }

            if (targetCpu != currentCpuLimit)
            {
                SetCpuPowerLimit(targetCpu);
            }

            WriteStateSnapshot(nvmeTemp, chassisTemp, deltaT, currentCpuLimit, maxCpuCeiling, stateTag, statusDesc, dwellTimer, probePenaltyTimer, pollSec);
            LogStateChange(nvmeTemp, chassisTemp, deltaT, currentCpuLimit, stateTag, statusDesc, pollSec);

            return pollSec;
        }

        private static void SetCpuPowerLimit(int percent)
        {
            percent = Math.Max(30, Math.Min(100, percent));
            try
            {
                uint res1 = PowerWriteACValueIndex(
                    IntPtr.Zero,
                    ref activeSchemeGuid,
                    ref GUID_PROCESSOR_SETTINGS_SUBGROUP,
                    ref GUID_PROCTHROTTLEMAX,
                    (uint)percent
                );

                uint res2 = PowerSetActiveScheme(IntPtr.Zero, ref activeSchemeGuid);

                if (res1 == 0 && res2 == 0)
                {
                    currentCpuLimit = percent;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[ERROR] Power Setting P/Invoke Failed: " + ex.Message);
            }
        }

        private static int GetNvmeDieTemperature()
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"(Get-PhysicalDisk | Get-StorageReliabilityCounter).Temperature\"";
                psi.RedirectStandardOutput = true;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;

                using (Process p = Process.Start(psi))
                {
                    string output = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(3000);
                    
                    string[] lines = output.Split(new char[] { '\r', '\n', ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string token in lines)
                    {
                        int temp;
                        if (int.TryParse(token.Trim(), out temp))
                        {
                            if (temp >= 20 && temp <= 110)
                            {
                                return temp;
                            }
                        }
                    }
                }
            }
            catch { }
            return -1;
        }

        private static int GetChassisAcpiTemperature()
        {
            try
            {
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(@"root\wmi", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature"))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        uint raw = (uint)obj["CurrentTemperature"];
                        int celsius = (int)((raw - 2732) / 10);
                        if (celsius >= 15 && celsius <= 100) return celsius;
                    }
                }
            }
            catch { }
            return 30; // Nominal ambient fallback
        }

        private static void WriteStateSnapshot(int nvmeTemp, int chassisTemp, int deltaT, int cpuLimit, int ceiling, string tag, string status, int dwell, int penalty, int pollSec)
        {
            try
            {
                int reqDwell = inEmergencyCooldown ? COLD_SOAK_DWELL_SEC : STANDARD_DWELL_SEC;
                int remDwell = Math.Max(0, reqDwell - dwell);
                string json = string.Format(
                    "{{\n" +
                    "  \"timestamp\": \"{0}\",\n" +
                    "  \"nvmeTempC\": {1},\n" +
                    "  \"chassisTempC\": {2},\n" +
                    "  \"thermalDelta\": {3},\n" +
                    "  \"temperatureC\": {1},\n" +
                    "  \"cpuLimitPercent\": {4},\n" +
                    "  \"maxCeiling\": {5},\n" +
                    "  \"stateTag\": \"{6}\",\n" +
                    "  \"status\": \"{7}\",\n" +
                    "  \"dwellElapsed\": {8},\n" +
                    "  \"dwellRemaining\": {9},\n" +
                    "  \"probePenaltyRemaining\": {10},\n" +
                    "  \"pollIntervalSec\": {11}\n" +
                    "}}",
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                    nvmeTemp,
                    chassisTemp,
                    deltaT,
                    cpuLimit,
                    ceiling,
                    tag,
                    status,
                    dwell,
                    remDwell,
                    penalty,
                    pollSec
                );

                string tempFile = STATE_FILE + ".tmp";
                File.WriteAllText(tempFile, json, new UTF8Encoding(false)); // Write UTF-8 WITHOUT BOM
                if (File.Exists(STATE_FILE)) File.Delete(STATE_FILE);
                File.Move(tempFile, STATE_FILE);
            }
            catch { }
        }

        private static void LogStateChange(int nvmeTemp, int chassisTemp, int deltaT, int cpuLimit, string tag, string status, int pollSec)
        {
            if (cpuLimit != lastLoggedCpu || Math.Abs(nvmeTemp - lastLoggedTemp) >= 2)
            {
                lastLoggedCpu = cpuLimit;
                lastLoggedTemp = nvmeTemp;

                string logFile = Path.Combine(LOG_DIR, "nvme_thermal_" + DateTime.Now.ToString("yyyy-MM-dd") + ".csv");
                bool isNew = !File.Exists(logFile);

                try
                {
                    using (StreamWriter sw = new StreamWriter(logFile, true, Encoding.UTF8))
                    {
                        if (isNew)
                        {
                            sw.WriteLine("Timestamp,NVMeTempC,ChassisTempC,DeltaT,CpuLimitPercent,PollIntervalSec,StateTag,Status");
                        }
                        sw.WriteLine(string.Format("{0},{1},{2},{3},{4},{5},{6},{7}",
                            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                            nvmeTemp,
                            chassisTemp,
                            deltaT,
                            cpuLimit,
                            pollSec,
                            tag,
                            status
                        ));
                    }

                    Console.WriteLine(string.Format("[{0}] [{1}] NVMe: {2}°C | Chassis: {3}°C (Δ {4}°C) | CPU: {5}% | {6}",
                        DateTime.Now.ToString("HH:mm:ss"),
                        tag,
                        nvmeTemp,
                        chassisTemp,
                        deltaT,
                        cpuLimit,
                        status
                    ));
                }
                catch { }
            }
        }

        private static void CheckControlOverrides()
        {
            try
            {
                if (File.Exists(CONTROL_FILE))
                {
                    string text = File.ReadAllText(CONTROL_FILE).Trim();
                    int overrideCeiling;
                    if (int.TryParse(text, out overrideCeiling))
                    {
                        if (overrideCeiling >= 50 && overrideCeiling <= 100 && overrideCeiling != maxCpuCeiling)
                        {
                            maxCpuCeiling = overrideCeiling;
                            Console.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss") + "] [CONTROL] Max CPU Ceiling Updated: " + maxCpuCeiling + "%");
                        }
                    }
                    File.Delete(CONTROL_FILE);
                }
            }
            catch { }
        }

        private static void PurgeOldLogs()
        {
            try
            {
                if (Directory.Exists(LOG_DIR))
                {
                    DateTime cutoff = DateTime.Now.AddDays(-7);
                    foreach (string file in Directory.GetFiles(LOG_DIR, "nvme_thermal_*.csv"))
                    {
                        FileInfo fi = new FileInfo(file);
                        if (fi.LastWriteTime < cutoff)
                        {
                            fi.Delete();
                        }
                    }
                }
            }
            catch { }
        }
    }
}
