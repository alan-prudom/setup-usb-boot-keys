using System;
using System.IO;
using System.Net;
using System.Text;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;

namespace NVMeThermal
{
    public class TrayApp : Form
    {
        private const string STATE_FILE = @"D:\nvme_state.json";
        private const string CONTROL_FILE = @"D:\nvme_control.json";
        private const int WEB_PORT = 8550;

        private NotifyIcon notifyIcon;
        private ContextMenuStrip contextMenu;
        private System.Windows.Forms.Timer pollTimer;
        private HttpListener httpListener;
        private Thread webThread;
        private int lastNotifiedCpu = -1;

        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new TrayApp());
        }

        public TrayApp()
        {
            this.WindowState = FormWindowState.Minimized;
            this.ShowInTaskbar = false;
            this.Visible = false;

            // Setup Context Menu
            contextMenu = new ContextMenuStrip();
            contextMenu.Items.Add("NVMe Thermal Monitor", null, (s, e) => OpenWebDashboard()).Font = new Font(FontFamily.GenericSansSerif, 9, FontStyle.Bold);
            contextMenu.Items.Add(new ToolStripSeparator());
            
            ToolStripMenuItem ceilingMenu = new ToolStripMenuItem("Set Max CPU Ceiling");
            ceilingMenu.DropDownItems.Add("70% Max", null, (s, e) => SetCeilingOverride(70));
            ceilingMenu.DropDownItems.Add("75% Max (Default)", null, (s, e) => SetCeilingOverride(75));
            ceilingMenu.DropDownItems.Add("80% Max", null, (s, e) => SetCeilingOverride(80));
            ceilingMenu.DropDownItems.Add("85% Max", null, (s, e) => SetCeilingOverride(85));
            ceilingMenu.DropDownItems.Add("90% Max", null, (s, e) => SetCeilingOverride(90));
            contextMenu.Items.Add(ceilingMenu);

            contextMenu.Items.Add("Open Web Dashboard", null, (s, e) => OpenWebDashboard());
            contextMenu.Items.Add(new ToolStripSeparator());
            contextMenu.Items.Add("Exit Tray Monitor", null, (s, e) => ExitApp());

            // Setup Notify Icon
            notifyIcon = new NotifyIcon();
            notifyIcon.ContextMenuStrip = contextMenu;
            notifyIcon.Visible = true;
            notifyIcon.DoubleClick += (s, e) => OpenWebDashboard();
            UpdateTrayIcon(44, 70, "Initializing...");

            // Setup Polling Timer
            pollTimer = new System.Windows.Forms.Timer();
            pollTimer.Interval = 2000;
            pollTimer.Tick += (s, e) => RefreshState();
            pollTimer.Start();

            // Start Embedded Micro Web Server
            StartWebServer();
        }

        private void RefreshState()
        {
            try
            {
                if (File.Exists(STATE_FILE))
                {
                    string json = File.ReadAllText(STATE_FILE, Encoding.UTF8);
                    int nvmeTemp = ParseJsonInt(json, "nvmeTempC", ParseJsonInt(json, "temperatureC", 44));
                    int chassisTemp = ParseJsonInt(json, "chassisTempC", 30);
                    int cpu = ParseJsonInt(json, "cpuLimitPercent", 70);
                    int ceiling = ParseJsonInt(json, "maxCeiling", 75);
                    string stateTag = ParseJsonString(json, "stateTag", "Normal");

                    string tip = string.Format("NVMe: {0}°C | Chassis: {1}°C | CPU: {2}% (Max {3}%)\nState: {4}", nvmeTemp, chassisTemp, cpu, ceiling, stateTag);
                    UpdateTrayIcon(nvmeTemp, cpu, tip);

                    if (lastNotifiedCpu != -1 && cpu < lastNotifiedCpu && cpu <= 60)
                    {
                        notifyIcon.ShowBalloonTip(4000, "🛡️ NVMe Thermal Safeguard", string.Format("Temperature reached {0}°C. Stepped DOWN CPU power: {1}% -> {2}%", nvmeTemp, lastNotifiedCpu, cpu), ToolTipIcon.Warning);
                    }
                    lastNotifiedCpu = cpu;
                }
            }
            catch { }
        }

        private void UpdateTrayIcon(int temp, int cpu, string tooltip)
        {
            try
            {
                Bitmap bmp = new Bitmap(16, 16);
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    Color bgColor = (temp >= 57) ? Color.DarkRed : (temp >= 55) ? Color.DarkMagenta : (temp >= 51) ? Color.DarkOrange : Color.DarkGreen;
                    g.Clear(bgColor);
                    using (Brush brush = new SolidBrush(Color.White))
                    using (Font font = new Font(FontFamily.GenericSansSerif, 8, FontStyle.Bold))
                    {
                        string txt = temp.ToString();
                        g.DrawString(txt, font, brush, -2, 1);
                    }
                }
                IntPtr hIcon = bmp.GetHicon();
                Icon icon = Icon.FromHandle(hIcon);
                notifyIcon.Icon = icon;
                notifyIcon.Text = tooltip.Length > 63 ? tooltip.Substring(0, 63) : tooltip;
            }
            catch { }
        }

        private void SetCeilingOverride(int percent)
        {
            try
            {
                File.WriteAllText(CONTROL_FILE, percent.ToString(), Encoding.UTF8);
                notifyIcon.ShowBalloonTip(2000, "NVMe Thermal Governor", "Requested Max CPU Ceiling: " + percent + "%", ToolTipIcon.Info);
            }
            catch { }
        }

        private void OpenWebDashboard()
        {
            try
            {
                System.Diagnostics.Process.Start("http://localhost:" + WEB_PORT);
            }
            catch { }
        }

        private void StartWebServer()
        {
            try
            {
                httpListener = new HttpListener();
                try
                {
                    httpListener.Prefixes.Add("http://*:" + WEB_PORT + "/");
                }
                catch
                {
                    httpListener.Prefixes.Clear();
                    httpListener.Prefixes.Add("http://localhost:" + WEB_PORT + "/");
                    httpListener.Prefixes.Add("http://127.0.0.1:" + WEB_PORT + "/");
                }

                try
                {
                    httpListener.Start();
                }
                catch
                {
                    // Fallback to pure localhost
                    httpListener.Close();
                    httpListener = new HttpListener();
                    httpListener.Prefixes.Add("http://localhost:" + WEB_PORT + "/");
                    httpListener.Prefixes.Add("http://127.0.0.1:" + WEB_PORT + "/");
                    httpListener.Start();
                }

                webThread = new Thread(() =>
                {
                    while (httpListener.IsListening)
                    {
                        try
                        {
                            HttpListenerContext ctx = httpListener.GetContext();
                            ThreadPool.QueueUserWorkItem((state) => HandleRequest(ctx));
                        }
                        catch { }
                    }
                });
                webThread.IsBackground = true;
                webThread.Start();
            }
            catch (Exception ex)
            {
                Console.WriteLine("Web server error: " + ex.Message);
            }
        }

        private void HandleRequest(HttpListenerContext ctx)
        {
            try
            {
                string rawUrl = ctx.Request.RawUrl;
                if (rawUrl.StartsWith("/api/state"))
                {
                    string json = File.Exists(STATE_FILE) ? File.ReadAllText(STATE_FILE, Encoding.UTF8) : "{}";
                    byte[] data = Encoding.UTF8.GetBytes(json);
                    ctx.Response.ContentType = "application/json";
                    ctx.Response.OutputStream.Write(data, 0, data.Length);
                }
                else
                {
                    string html = GetDashboardHtml();
                    byte[] data = Encoding.UTF8.GetBytes(html);
                    ctx.Response.ContentType = "text/html; charset=utf-8";
                    ctx.Response.OutputStream.Write(data, 0, data.Length);
                }
                ctx.Response.Close();
            }
            catch { }
        }

        private string GetDashboardHtml()
        {
            return @"<!DOCTYPE html>
<html>
<head>
    <title>NVMe Predictive Thermal Governor</title>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 20px; display: flex; justify-content: center; }
        .card { background: #1e293b; border-radius: 16px; padding: 24px; max-width: 650px; width: 100%; box-shadow: 0 10px 25px rgba(0,0,0,0.5); border: 1px solid #334155; }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #334155; padding-bottom: 16px; margin-bottom: 20px; }
        h1 { margin: 0; font-size: 20px; color: #38bdf8; }
        .gauge-container { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; margin-bottom: 20px; }
        .gauge { background: #0f172a; border-radius: 12px; padding: 16px; text-align: center; border: 1px solid #334155; }
        .gauge-val { font-size: 36px; font-weight: bold; margin: 6px 0; }
        .gauge-label { color: #94a3b8; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; }
        .temp-cold { color: #34d399; }
        .temp-warm { color: #fbbf24; }
        .temp-hot { color: #f87171; }
        .status-pill { display: inline-block; padding: 4px 12px; border-radius: 9999px; font-size: 12px; font-weight: bold; background: #0369a1; color: #e0f2fe; }
        .meta { font-size: 13px; color: #94a3b8; line-height: 1.8; background: #0f172a; padding: 16px; border-radius: 12px; border: 1px solid #334155; }
    </style>
</head>
<body>
    <div class='card'>
        <div class='header'>
            <h1>🛡️ Dual-Sensor NVMe Governor</h1>
            <span class='status-pill' id='stateTag'>Connecting...</span>
        </div>
        <div class='gauge-container'>
            <div class='gauge'>
                <div class='gauge-label'>NVMe Controller Die</div>
                <div class='gauge-val temp-cold' id='nvmeVal'>-- °C</div>
                <div style='font-size: 11px; color: #64748b;'>Limit: 55°C</div>
            </div>
            <div class='gauge'>
                <div class='gauge-label'>Chassis ACPI Zone</div>
                <div class='gauge-val' style='color: #60a5fa;' id='chassisVal'>-- °C</div>
                <div style='font-size: 11px; color: #64748b;'>Airflow Ceiling: 38°C</div>
            </div>
            <div class='gauge'>
                <div class='gauge-label'>CPU Power Limit</div>
                <div class='gauge-val' style='color: #38bdf8;' id='cpuVal'>-- %</div>
                <div style='font-size: 11px; color: #64748b;' id='ceilingVal'>Max: --%</div>
            </div>
        </div>
        <div class='meta'>
            <div><b>Thermal Gradient (ΔT):</b> <span id='deltaVal' style='color: #38bdf8; font-weight: bold;'>-- °C</span> (<span id='dissipationVal'>Healthy</span>)</div>
            <div><b>Status:</b> <span id='statusVal'>--</span></div>
            <div><b>Stability Dwell Remaining:</b> <span id='dwellVal'>--</span>s</div>
            <div><b>Probe Penalty Cooldown:</b> <span id='penaltyVal'>--</span>s</div>
            <div><b>Last Updated:</b> <span id='timeVal'>--</span></div>
        </div>
    </div>
    <script>
        async function fetchState() {
            try {
                const res = await fetch('/api/state');
                const data = await res.json();
                const nvme = data.nvmeTempC || data.temperatureC;
                document.getElementById('nvmeVal').innerText = nvme + ' °C';
                document.getElementById('nvmeVal').className = 'gauge-val ' + (nvme >= 55 ? 'temp-hot' : nvme >= 51 ? 'temp-warm' : 'temp-cold');
                document.getElementById('chassisVal').innerText = (data.chassisTempC || '--') + ' °C';
                document.getElementById('deltaVal').innerText = (data.thermalDelta || (nvme - (data.chassisTempC || 0))) + ' °C';
                document.getElementById('dissipationVal').innerText = (data.thermalDelta >= 8) ? 'Efficient Dissipation' : 'Saturated / Stagnant';
                document.getElementById('cpuVal').innerText = data.cpuLimitPercent + ' %';
                document.getElementById('ceilingVal').innerText = 'Max: ' + data.maxCeiling + '%';
                document.getElementById('stateTag').innerText = data.stateTag || 'ACTIVE';
                document.getElementById('timeVal').innerText = data.timestamp;
                document.getElementById('statusVal').innerText = data.status;
                document.getElementById('dwellVal').innerText = data.dwellRemaining;
                document.getElementById('penaltyVal').innerText = data.probePenaltyRemaining;
            } catch(e) {}
        }
        setInterval(fetchState, 1500);
        fetchState();
    </script>
</body>
</html>";
        }

        private int ParseJsonInt(string json, string key, int defVal)
        {
            try
            {
                string search = "\"" + key + "\":";
                int idx = json.IndexOf(search);
                if (idx != -1)
                {
                    int start = idx + search.Length;
                    int end = json.IndexOfAny(new char[] { ',', '\n', '}' }, start);
                    if (end != -1)
                    {
                        return int.Parse(json.Substring(start, end - start).Trim());
                    }
                }
            }
            catch { }
            return defVal;
        }

        private string ParseJsonString(string json, string key, string defVal)
        {
            try
            {
                string search = "\"" + key + "\": \"";
                int idx = json.IndexOf(search);
                if (idx != -1)
                {
                    int start = idx + search.Length;
                    int end = json.IndexOf("\"", start);
                    if (end != -1)
                    {
                        return json.Substring(start, end - start);
                    }
                }
            }
            catch { }
            return defVal;
        }

        private void ExitApp()
        {
            pollTimer.Stop();
            if (httpListener != null) { try { httpListener.Stop(); } catch { } }
            notifyIcon.Visible = false;
            Application.Exit();
        }

        protected override void SetVisibleCore(bool value)
        {
            base.SetVisibleCore(false);
        }
    }
}
