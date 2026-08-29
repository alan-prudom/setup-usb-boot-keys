# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import os
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

# Force UTF-8 standard output for Windows console compatibility
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

STATE_FILE = r"D:\nvme_state.json"
DEFAULT_PORTS = [8899, 8088, 9090, 8585, 8550]

DASHBOARD_HTML = """<!DOCTYPE html>
<html lang='en' data-theme='light'>
<head>
    <title>NVMe Predictive Thermal Governor</title>
    <meta name='viewport' content='width=device-width, initial-scale=1'>
    <style>
        :root[data-theme='light'] {
            --bg: #f1f5f9;
            --card-bg: #ffffff;
            --inner-bg: #f8fafc;
            --text-main: #0f172a;
            --text-muted: #475569;
            --border: #cbd5e1;
            --accent: #0284c7;
            --pill-bg: #e0f2fe;
            --pill-text: #0369a1;
            --temp-cold: #15803d;
            --temp-warm: #b45309;
            --temp-hot: #b91c1c;
        }
        :root[data-theme='dark'] {
            --bg: #0f172a;
            --card-bg: #1e293b;
            --inner-bg: #0f172a;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --border: #334155;
            --accent: #38bdf8;
            --pill-bg: #0369a1;
            --pill-text: #e0f2fe;
            --temp-cold: #34d399;
            --temp-warm: #fbbf24;
            --temp-hot: #f87171;
        }

        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
            background: var(--bg); 
            color: var(--text-main); 
            margin: 0; 
            padding: 24px; 
            display: flex; 
            justify-content: center; 
            transition: background 0.3s, color 0.3s;
        }
        .card { 
            background: var(--card-bg); 
            border-radius: 16px; 
            padding: 24px; 
            max-width: 680px; 
            width: 100%; 
            box-shadow: 0 10px 25px rgba(0,0,0,0.08); 
            border: 1px solid var(--border); 
            transition: background 0.3s, border-color 0.3s;
        }
        .header { 
            display: flex; 
            justify-content: space-between; 
            align-items: center; 
            border-bottom: 1px solid var(--border); 
            padding-bottom: 16px; 
            margin-bottom: 20px; 
        }
        h1 { margin: 0; font-size: 20px; color: var(--accent); font-weight: 700; }
        .header-controls { display: flex; gap: 10px; align-items: center; }
        .theme-btn {
            background: var(--inner-bg);
            border: 1px solid var(--border);
            color: var(--text-main);
            padding: 6px 12px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 600;
            transition: all 0.2s;
        }
        .theme-btn:hover { border-color: var(--accent); }
        .gauge-container { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; margin-bottom: 20px; }
        .gauge { 
            background: var(--inner-bg); 
            border-radius: 12px; 
            padding: 16px; 
            text-align: center; 
            border: 1px solid var(--border); 
            transition: background 0.3s, border-color 0.3s;
        }
        .gauge-val { font-size: 38px; font-weight: 800; margin: 6px 0; }
        .gauge-label { color: var(--text-muted); font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; }
        .temp-cold { color: var(--temp-cold); }
        .temp-warm { color: var(--temp-warm); }
        .temp-hot { color: var(--temp-hot); }
        .status-pill { display: inline-block; padding: 4px 12px; border-radius: 9999px; font-size: 12px; font-weight: 700; background: var(--pill-bg); color: var(--pill-text); }
        .meta { 
            font-size: 13px; 
            color: var(--text-muted); 
            line-height: 1.9; 
            background: var(--inner-bg); 
            padding: 18px; 
            border-radius: 12px; 
            border: 1px solid var(--border); 
            transition: background 0.3s, border-color 0.3s;
        }
        .meta b { color: var(--text-main); }
    </style>
</head>
<body>
    <div class='card'>
        <div class='header'>
            <h1>[SAFEGUARD] Dual-Sensor NVMe Governor</h1>
            <div class='header-controls'>
                <span class='status-pill' id='stateTag'>Connecting...</span>
                <button class='theme-btn' onclick='toggleTheme()' id='themeBtn'>Dark Mode</button>
            </div>
        </div>
        <div class='gauge-container'>
            <div class='gauge'>
                <div class='gauge-label'>NVMe Controller Die</div>
                <div class='gauge-val temp-cold' id='nvmeVal'>-- °C</div>
                <div style='font-size: 11px; color: var(--text-muted);'>Floor Safe &le; 50°C | Limit 55°C</div>
            </div>
            <div class='gauge'>
                <div class='gauge-label'>Chassis ACPI Zone</div>
                <div class='gauge-val' style='color: var(--accent);' id='chassisVal'>-- °C</div>
                <div style='font-size: 11px; color: var(--text-muted);'>Airflow Soak Ceiling 38°C</div>
            </div>
            <div class='gauge'>
                <div class='gauge-label'>CPU Power Limit</div>
                <div class='gauge-val' style='color: var(--accent);' id='cpuVal'>-- %</div>
                <div style='font-size: 11px; color: var(--text-muted);' id='ceilingVal'>Max: --%</div>
            </div>
        </div>
        <div class='meta'>
            <div><b>Thermal Gradient (&Delta;T):</b> <span id='deltaVal' style='color: var(--accent); font-weight: bold;'>-- °C</span> (<span id='dissipationVal' style='font-weight: bold;'>Healthy</span>)</div>
            <div><b>Governor Status:</b> <span id='statusVal'>--</span></div>
            <div><b>Stability Dwell Remaining:</b> <span id='dwellVal' style='color: var(--temp-cold); font-weight: bold;'>--</span>s</div>
            <div><b>Probe Penalty Cooldown:</b> <span id='penaltyVal' style='color: var(--temp-warm); font-weight: bold;'>--</span>s</div>
            <div><b>Last Telemetry Stream:</b> <span id='timeVal'>--</span></div>
        </div>
    </div>
    <script>
        function applyTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            localStorage.setItem('nvme_theme', theme);
            document.getElementById('themeBtn').innerText = (theme === 'light') ? 'Dark Mode' : 'Light Mode';
        }
        function toggleTheme() {
            const current = document.documentElement.getAttribute('data-theme') || 'light';
            const next = (current === 'light') ? 'dark' : 'light';
            applyTheme(next);
        }
        // Initialize Default Theme to Light
        const saved = localStorage.getItem('nvme_theme') || 'light';
        applyTheme(saved);

        async function fetchState() {
            try {
                const res = await fetch('/api/state');
                const data = await res.json();
                const nvme = data.nvmeTempC || data.temperatureC;
                document.getElementById('nvmeVal').innerText = nvme + ' °C';
                document.getElementById('nvmeVal').className = 'gauge-val ' + (nvme >= 55 ? 'temp-hot' : nvme >= 51 ? 'temp-warm' : 'temp-cold');
                document.getElementById('chassisVal').innerText = (data.chassisTempC || '--') + ' °C';
                document.getElementById('deltaVal').innerText = (data.thermalDelta || (nvme - (data.chassisTempC || 0))) + ' °C';
                document.getElementById('dissipationVal').innerText = (data.thermalDelta >= 8) ? 'Efficient Die-to-Ambient Dissipation' : 'Saturated / Stagnant Airflow';
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
</html>"""

class DashboardHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/state"):
            if os.path.exists(STATE_FILE):
                try:
                    with open(STATE_FILE, "r", encoding="utf-8-sig") as f:
                        data = f.read().encode("utf-8")
                except Exception:
                    data = b"{}"
            else:
                data = b"{}"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            data = DASHBOARD_HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    def log_message(self, format, *args):
        pass

def run():
    server = None
    active_port = None
    for p in DEFAULT_PORTS:
        try:
            server = HTTPServer(("0.0.0.0", p), DashboardHandler)
            active_port = p
            break
        except Exception:
            continue

    if not server:
        print("[ERROR] Could not bind to candidate ports (8899, 8088, 9090, 8585).")
        sys.exit(1)

    print(f"[OK] NVMe Thermal Web Dashboard running at http://localhost:{active_port}")
    print(f"[URL] Remote access via Tailscale: http://100.127.153.93:{active_port}")
    server.serve_forever()

if __name__ == "__main__":
    run()
