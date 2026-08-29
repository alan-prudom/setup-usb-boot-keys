using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Management;
using System.Runtime.InteropServices;

namespace NVMeThermal
{
    public class Daemon
    {
        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerGetActiveScheme(IntPtr UserRootPowerKey, out IntPtr ActivePolicyGuid);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerWriteACValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, uint AcValueIndex);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerWriteDCValueIndex(IntPtr RootPowerKey, ref Guid SchemeGuid, ref Guid SubGroupOfPowerSettingsGuid, ref Guid PowerSettingGuid, uint DcValueIndex);

        [DllImport("powrprof.dll", SetLastError = true)]
        private static extern uint PowerSetActiveScheme(IntPtr UserRootPowerKey, ref Guid SchemeGuid);

        private static readonly Guid GUID_PROCESSOR_SETTINGS_SUBGROUP = new Guid("54533251-82be-4824-96c1-47b60b740d00");
        private static readonly Guid GUID_PROCESSOR_THROTTLE_MAX = new Guid("bc5038f7-23e0-4960-96da-33abaf5935ec");

        private const string STATE_FILE = @"D:\nvme_state.json";
        private const string CONTROL_FILE = @"D:\nvme_control.json";
        private const string LOG_DIR = @"D:\logs";
        private const int DWELL_SECONDS = 30;
        private const int PROBE_PENALTY_DEFAULT = 60;
        private const int LOG_RETENTION_DAYS = 7;

        private static int maxCeiling = 75;
        private static int currentCpuLimit = 70;
        private static int stableBelowCounter = 0;
        private static int probePenaltyCounter = 0;
        private static int lastLoggedNvmeTemp = -1;
        private static int lastLoggedChassisTemp = -1;
        private static int lastLoggedCpu = -1;
        private static string lastLoggedState = "";

        public static void Main(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                if ((args[i] == "-MaxCpu" || args[i] == "--max-cpu") && i + 1 < args.Length)
                {
                    int val;
                    if (int.TryParse(args[i + 1], out val) && val >= 40 && val <= 100)
                    {
                        maxCeiling = val;
                    }
                }
            }

            Console.WriteLine("==========================================================");
            Console.WriteLine("  Dual-Sensor Predictive NVMe Thermal Governor (C# Native)");
            Console.WriteLine("==========================================================");
            Console.WriteLine("  Max CPU Ceiling  : " + maxCeiling + "%");
            Console.WriteLine("  Sensors Monitored: Samsung NVMe Die + Chassis ACPI Zone");
            Console.WriteLine("  State Output     : " + STATE_FILE);
            Console.WriteLine("  Log Directory    : " + LOG_DIR + " (7-day rotation, state-change only)");
            Console.WriteLine("----------------------------------------------------------");

            if (!Directory.Exists(LOG_DIR))
            {
                Directory.CreateDirectory(LOG_DIR);
            }

            currentCpuLimit = Math.Min(70, maxCeiling);
            SetCpuPowerLimit(currentCpuLimit);

            while (true)
            {
                DateTime now = DateTime.Now;
                CheckControlOverrides();
                PurgeOldLogs();

                int? nvmeTemp = ReadNVMeTemperature();
                int? chassisTemp = ReadChassisTemperature();

                if (!nvmeTemp.HasValue)
                {
                    Console.WriteLine("[" + now.ToString("HH:mm:ss") + "] [WARN] NVMe temp read failed. Retrying in 4s...");
                    Thread.Sleep(4000);
                    continue;
                }

                int currentNvme = nvmeTemp.Value;
                int currentChassis = chassisTemp.HasValue ? chassisTemp.Value : 0;
                int deltaT = currentNvme - currentChassis;

                if (probePenaltyCounter > 0)
                {
                    probePenaltyCounter = Math.Max(0, probePenaltyCounter - 4);
                }

                int pollInterval = 4;
                string stateTag = "SUSTAINED " + currentCpuLimit + "%";
                string statusMsg = "Sustained";
                bool powerChanged = false;

                // 1. Reactive Thermal Safety Ladder (Based on NVMe Die)
                if (currentNvme >= 59)
                {
                    pollInterval = 1;
                    stateTag = "CRITICAL 40%";
                    statusMsg = "CRITICAL_FLOOR";
                    if (currentCpuLimit > 40)
                    {
                        currentCpuLimit = 40;
                        probePenaltyCounter = 90;
                        stableBelowCounter = 0;
                        powerChanged = true;
                        SetCpuPowerLimit(40);
                    }
                }
                else if (currentNvme >= 57)
                {
                    pollInterval = 2;
                    stateTag = "DEEP 50%";
                    statusMsg = "DEEP_COOLING";
                    if (currentCpuLimit > 50)
                    {
                        currentCpuLimit = 50;
                        probePenaltyCounter = 60;
                        stableBelowCounter = 0;
                        powerChanged = true;
                        SetCpuPowerLimit(50);
                    }
                }
                else if (currentNvme >= 55)
                {
                    pollInterval = 3;
                    stateTag = "ACTIVE 60%";
                    statusMsg = "ACTIVE_COOLING";
                    if (currentCpuLimit > 60)
                    {
                        currentCpuLimit = 60;
                        probePenaltyCounter = PROBE_PENALTY_DEFAULT;
                        stableBelowCounter = 0;
                        powerChanged = true;
                        SetCpuPowerLimit(60);
                    }
                }
                else
                {
                    bool chassisHot = (currentChassis >= 38);
                    int targetMax = (currentNvme <= 50 && !chassisHot) ? maxCeiling : Math.Min(maxCeiling, 70);
                    stateTag = (currentNvme <= 50) ? ("OPTIMAL " + currentCpuLimit + "%") : ("SUSTAINED " + currentCpuLimit + "%");

                    if (currentCpuLimit > targetMax)
                    {
                        currentCpuLimit = targetMax;
                        powerChanged = true;
                        SetCpuPowerLimit(currentCpuLimit);
                        if (chassisHot) statusMsg = "CHASSIS_HEAT_CLAMP";
                    }
                    else if (currentCpuLimit < targetMax && probePenaltyCounter == 0)
                    {
                        stableBelowCounter += pollInterval;
                        if (stableBelowCounter >= DWELL_SECONDS)
                        {
                            currentCpuLimit = Math.Min(maxCeiling, currentCpuLimit + 5);
                            stableBelowCounter = 0;
                            powerChanged = true;
                            SetCpuPowerLimit(currentCpuLimit);
                            statusMsg = "PROBED_UP";
                        }
                    }
                    else
                    {
                        stableBelowCounter = 0;
                    }
                }

                Console.WriteLine(string.Format("[{0}] [{1}] NVMe: {2} C | Chassis: {3} C (Δ {4} C) | CPU: {5}% | Dwell: {6}s",
                    now.ToString("HH:mm:ss"), stateTag, currentNvme, currentChassis, deltaT, currentCpuLimit, Math.Max(0, DWELL_SECONDS - stableBelowCounter)));

                WriteStateJson(now, currentNvme, currentChassis, deltaT, currentCpuLimit, maxCeiling, stateTag, statusMsg, stableBelowCounter, probePenaltyCounter, pollInterval);

                if (currentNvme != lastLoggedNvmeTemp || currentChassis != lastLoggedChassisTemp || currentCpuLimit != lastLoggedCpu || stateTag != lastLoggedState || powerChanged)
                {
                    AppendDailyLog(now, currentNvme, currentChassis, deltaT, currentCpuLimit, pollInterval, stateTag, statusMsg);
                    lastLoggedNvmeTemp = currentNvme;
                    lastLoggedChassisTemp = currentChassis;
                    lastLoggedCpu = currentCpuLimit;
                    lastLoggedState = stateTag;
                }

                Thread.Sleep(pollInterval * 1000);
            }
        }

        private static int? ReadNVMeTemperature()
        {
            try
            {
                System.Diagnostics.ProcessStartInfo psi = new System.Diagnostics.ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -Command \"(Get-PhysicalDisk | Get-StorageReliabilityCounter).Temperature\"";
                psi.RedirectStandardOutput = true;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                using (System.Diagnostics.Process p = System.Diagnostics.Process.Start(psi))
                {
                    string outStr = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(3000);
                    
                    string[] tokens = outStr.Split(new char[] { '\r', '\n', ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string token in tokens)
                    {
                        int val;
                        if (int.TryParse(token, out val) && val > 20 && val < 120)
                        {
                            return val;
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        private static int? ReadChassisTemperature()
        {
            try
            {
                ManagementScope acpiScope = new ManagementScope(@"\\.\root\wmi");
                acpiScope.Connect();
                using (ManagementObjectSearcher s = new ManagementObjectSearcher(acpiScope, new ObjectQuery("SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature")))
                {
                    foreach (ManagementObject obj in s.Get())
                    {
                        object val = obj["CurrentTemperature"];
                        if (val != null)
                        {
                            int deciKelvin = Convert.ToInt32(val);
                            int celsius = (deciKelvin - 2732) / 10;
                            if (celsius > 10 && celsius < 110) return celsius;
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        private static void SetCpuPowerLimit(int percent)
        {
            try
            {
                IntPtr pActiveGuid;
                if (PowerGetActiveScheme(IntPtr.Zero, out pActiveGuid) == 0 && pActiveGuid != IntPtr.Zero)
                {
                    Guid activeScheme = (Guid)Marshal.PtrToStructure(pActiveGuid, typeof(Guid));
                    Guid subGroup = GUID_PROCESSOR_SETTINGS_SUBGROUP;
                    Guid setting = GUID_PROCESSOR_THROTTLE_MAX;

                    PowerWriteACValueIndex(IntPtr.Zero, ref activeScheme, ref subGroup, ref setting, (uint)percent);
                    PowerWriteDCValueIndex(IntPtr.Zero, ref activeScheme, ref subGroup, ref setting, (uint)percent);
                    PowerSetActiveScheme(IntPtr.Zero, ref activeScheme);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Error setting CPU power: " + ex.Message);
            }
        }

        private static void CheckControlOverrides()
        {
            try
            {
                if (File.Exists(CONTROL_FILE))
                {
                    string text = File.ReadAllText(CONTROL_FILE).Trim();
                    int overrideVal;
                    if (int.TryParse(text, out overrideVal) && overrideVal >= 40 && overrideVal <= 100)
                    {
                        maxCeiling = overrideVal;
                        Console.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss") + "] Received Control Override: Max Ceiling = " + maxCeiling + "%");
                    }
                    File.Delete(CONTROL_FILE);
                }
            }
            catch { }
        }

        private static void WriteStateJson(DateTime now, int nvmeTemp, int chassisTemp, int deltaT, int cpu, int ceiling, string stateTag, string status, int dwell, int penalty, int poll)
        {
            try
            {
                string json = string.Format(
                    "{{\n  \"timestamp\": \"{0}\",\n  \"nvmeTempC\": {1},\n  \"chassisTempC\": {2},\n  \"thermalDelta\": {3},\n  \"temperatureC\": {1},\n  \"cpuLimitPercent\": {4},\n  \"maxCeiling\": {5},\n  \"stateTag\": \"{6}\",\n  \"status\": \"{7}\",\n  \"dwellElapsed\": {8},\n  \"dwellRemaining\": {9},\n  \"probePenaltyRemaining\": {10},\n  \"pollIntervalSec\": {11}\n}}",
                    now.ToString("yyyy-MM-dd HH:mm:ss"),
                    nvmeTemp,
                    chassisTemp,
                    deltaT,
                    cpu,
                    ceiling,
                    stateTag,
                    status,
                    dwell,
                    Math.Max(0, DWELL_SECONDS - dwell),
                    penalty,
                    poll
                );

                string tmpFile = STATE_FILE + ".tmp";
                File.WriteAllText(tmpFile, json, Encoding.UTF8);
                if (File.Exists(STATE_FILE)) { File.Delete(STATE_FILE); }
                File.Move(tmpFile, STATE_FILE);
            }
            catch { }
        }

        private static void AppendDailyLog(DateTime now, int nvmeTemp, int chassisTemp, int deltaT, int cpu, int poll, string stateTag, string status)
        {
            try
            {
                string logFile = Path.Combine(LOG_DIR, "nvme_thermal_" + now.ToString("yyyy-MM-dd") + ".csv");
                if (!File.Exists(logFile))
                {
                    File.WriteAllText(logFile, "Timestamp,NVMeTempC,ChassisTempC,DeltaT,CpuLimitPercent,PollIntervalSec,StateTag,Status\n", Encoding.UTF8);
                }
                string line = string.Format("{0},{1},{2},{3},{4},{5},{6},{7}\n", now.ToString("yyyy-MM-dd HH:mm:ss"), nvmeTemp, chassisTemp, deltaT, cpu, poll, stateTag, status);
                File.AppendAllText(logFile, line, Encoding.UTF8);
            }
            catch { }
        }

        private static void PurgeOldLogs()
        {
            try
            {
                DateTime cutoff = DateTime.Now.AddDays(-LOG_RETENTION_DAYS);
                string[] files = Directory.GetFiles(LOG_DIR, "nvme_thermal_*.csv");
                foreach (string f in files)
                {
                    FileInfo fi = new FileInfo(f);
                    if (fi.CreationTime < cutoff && fi.LastWriteTime < cutoff)
                    {
                        File.Delete(f);
                        Console.WriteLine("Purged expired log file: " + fi.Name);
                    }
                }
            }
            catch { }
        }
    }
}
