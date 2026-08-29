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
        // Win32 Power Management P/Invoke APIs (Zero process spawn overhead)
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

        // Configuration Defaults
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
        private static int lastLoggedTemp = -1;
        private static int lastLoggedCpu = -1;
        private static string lastLoggedState = "";

        public static void Main(string[] args)
        {
            // Parse arguments
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
            Console.WriteLine("  NVMe Thermal Governor Background Daemon (C# Native)");
            Console.WriteLine("==========================================================");
            Console.WriteLine("  Max CPU Ceiling  : " + maxCeiling + "%");
            Console.WriteLine("  State Output     : " + STATE_FILE);
            Console.WriteLine("  Log Directory    : " + LOG_DIR + " (7-day rotation, state-change only)");
            Console.WriteLine("----------------------------------------------------------");

            if (!Directory.Exists(LOG_DIR))
            {
                Directory.CreateDirectory(LOG_DIR);
            }

            // Enforce initial safe power limit
            currentCpuLimit = Math.Min(70, maxCeiling);
            SetCpuPowerLimit(currentCpuLimit);

            while (true)
            {
                DateTime now = DateTime.Now;
                CheckControlOverrides();
                PurgeOldLogs();

                int? temp = ReadNVMeTemperature();
                if (!temp.HasValue)
                {
                    Thread.Sleep(4000);
                    continue;
                }

                int currentTemp = temp.Value;
                if (probePenaltyCounter > 0)
                {
                    probePenaltyCounter = Math.Max(0, probePenaltyCounter - 4);
                }

                int pollInterval = 4;
                string stateTag = "SUSTAINED " + currentCpuLimit + "%";
                string statusMsg = "Sustained";
                bool powerChanged = false;

                // 1. Temperature Threshold Matrix
                if (currentTemp >= 59)
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
                else if (currentTemp >= 57)
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
                else if (currentTemp >= 55)
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
                    // Temperature is <= 54 C (Safe Probing Band)
                    int targetMax = (currentTemp <= 50) ? maxCeiling : Math.Min(maxCeiling, 70);
                    stateTag = (currentTemp <= 50) ? ("OPTIMAL " + currentCpuLimit + "%") : ("SUSTAINED " + currentCpuLimit + "%");

                    if (currentCpuLimit > targetMax)
                    {
                        currentCpuLimit = targetMax;
                        powerChanged = true;
                        SetCpuPowerLimit(currentCpuLimit);
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

                // 2. Write Real-Time State JSON (Atomic)
                WriteStateJson(now, currentTemp, currentCpuLimit, maxCeiling, stateTag, statusMsg, stableBelowCounter, probePenaltyCounter, pollInterval);

                // 3. Conditional State-Change CSV Logging
                if (currentTemp != lastLoggedTemp || currentCpuLimit != lastLoggedCpu || stateTag != lastLoggedState || powerChanged)
                {
                    AppendDailyLog(now, currentTemp, currentCpuLimit, pollInterval, stateTag, statusMsg);
                    lastLoggedTemp = currentTemp;
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
                using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(@"root\Microsoft\Windows\Storage", "SELECT Temperature FROM MSFT_StorageReliabilityCounter"))
                {
                    foreach (ManagementObject obj in searcher.Get())
                    {
                        object val = obj["Temperature"];
                        if (val != null)
                        {
                            return Convert.ToInt32(val);
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

                    Console.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss") + "] Power Limit successfully set to " + percent + "%");
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

        private static void WriteStateJson(DateTime now, int temp, int cpu, int ceiling, string stateTag, string status, int dwell, int penalty, int poll)
        {
            try
            {
                string json = string.Format(
                    "{{\n  \"timestamp\": \"{0}\",\n  \"temperatureC\": {1},\n  \"cpuLimitPercent\": {2},\n  \"maxCeiling\": {3},\n  \"stateTag\": \"{4}\",\n  \"status\": \"{5}\",\n  \"dwellElapsed\": {6},\n  \"dwellRemaining\": {7},\n  \"probePenaltyRemaining\": {8},\n  \"pollIntervalSec\": {9}\n}}",
                    now.ToString("yyyy-MM-dd HH:mm:ss"),
                    temp,
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

        private static void AppendDailyLog(DateTime now, int temp, int cpu, int poll, string stateTag, string status)
        {
            try
            {
                string logFile = Path.Combine(LOG_DIR, "nvme_thermal_" + now.ToString("yyyy-MM-dd") + ".csv");
                if (!File.Exists(logFile))
                {
                    File.WriteAllText(logFile, "Timestamp,TemperatureC,CpuLimitPercent,PollIntervalSec,StateTag,Status\n", Encoding.UTF8);
                }
                string line = string.Format("{0},{1},{2},{3},{4},{5}\n", now.ToString("yyyy-MM-dd HH:mm:ss"), temp, cpu, poll, stateTag, status);
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
