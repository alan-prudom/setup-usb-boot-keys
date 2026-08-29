# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import os
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

STATE_FILE = r"D:\nvme_state.json"
PORT = 8550

DASHBOARD_HTML = """<!DOCTYPE html>
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
    server = HTTPServer(("0.0.0.0", PORT), DashboardHandler)
    print(f"🛡️  NVMe Thermal Web Dashboard running at http://localhost:{PORT}")
    print(f"🌐 Remote access via Tailscale: http://100.127.153.93:{PORT}")
    server.serve_forever()

if __name__ == "__main__":
    run()
