# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "rich",
#     "textual",
# ]
# ///

import os
import sys
import json
import time
from datetime import datetime
from rich.console import Console
from rich.panel import Panel
from rich.layout import Layout
from rich.table import Table
from rich.text import Text
from rich.live import Live
from rich import box

STATE_FILE = r"D:\nvme_state.json"
CONTROL_FILE = r"D:\nvme_control.json"

console = Console()
last_debug_err = "Ready"

def read_state():
    global last_debug_err
    if not os.path.exists(STATE_FILE):
        last_debug_err = f"File not found: {STATE_FILE}"
        return None
    for _ in range(3):
        try:
            with open(STATE_FILE, "r", encoding="utf-8-sig") as f:
                content = f.read().strip()
                if content.startswith("{") and content.endswith("}"):
                    data = json.loads(content)
                    last_debug_err = f"Stream Active ({datetime.now().strftime('%H:%M:%S')})"
                    return data
        except Exception as e:
            last_debug_err = f"Error: {str(e)}"
            time.sleep(0.05)
    return None

def set_ceiling_override(val: int):
    try:
        with open(CONTROL_FILE, "w", encoding="utf-8") as f:
            f.write(str(val))
    except Exception:
        pass

def generate_dashboard(data):
    layout = Layout()
    layout.split_column(
        Layout(name="header", size=3),
        Layout(name="main", size=13),
        Layout(name="footer", size=3)
    )

    # Header - High-Contrast Dark Blue / Dark Cyan
    header_text = Text("  NVMe Dual-Sensor Predictive Governor & Telemetry", style="bold dark_blue")
    header_panel = Panel(header_text, style="bold dark_blue", subtitle=datetime.now().strftime("%Y-%m-%d %H:%M:%S"), box=box.ROUNDED)
    layout["header"].update(header_panel)

    if not data:
        debug_info = f"[dark_goldenrod]Waiting for Daemon State Snapshot...[/dark_goldenrod]\n\n[bold black]Status:[/bold black] [dark_red]{last_debug_err}[/dark_red]"
        layout["main"].update(Panel(debug_info, title="[bold dark_red]State Loading[/bold dark_red]", box=box.ROUNDED))
        layout["footer"].update(Panel(Text("Controls: [Ctrl+C] Exit", style="bold black"), box=box.ROUNDED))
        return layout

    nvme_temp = data.get("nvmeTempC", data.get("temperatureC", 0))
    chassis_temp = data.get("chassisTempC", 0)
    delta_t = data.get("thermalDelta", nvme_temp - chassis_temp)
    cpu = data.get("cpuLimitPercent", 0)
    ceiling = data.get("maxCeiling", 75)
    state_tag = data.get("stateTag", "N/A")
    dwell = data.get("dwellRemaining", 0)
    penalty = data.get("probePenaltyRemaining", 0)
    status = data.get("status", "N/A")

    # High-Contrast Light-Mode Palette (Dark tones on light backgrounds)
    if nvme_temp >= 57:
        nvme_style = "bold dark_red"
    elif nvme_temp >= 55:
        nvme_style = "bold dark_magenta"
    elif nvme_temp >= 51:
        nvme_style = "bold dark_goldenrod"
    else:
        nvme_style = "bold dark_green"

    # Main Telemetry Table with Strict Column Width Alignment
    table = Table(expand=True, box=box.SIMPLE_HEAVY)
    table.add_column("Sensor / Domain", width=25, justify="left", style="bold black")
    table.add_column("Reading", width=14, justify="center")
    table.add_column("Thermal Trajectory & Status Bar", justify="left")

    # NVMe Controller Die Row
    nvme_bar = "█" * int(min(20, max(1, (nvme_temp - 30) / 1.5)))
    table.add_row("NVMe Controller Die", f"[{nvme_style}]{nvme_temp} °C[/{nvme_style}]", f"[{nvme_style}]{nvme_bar}[/{nvme_style}] [black](Floor Safe <= 50°C | Limit 55°C)[/black]")

    # Chassis ACPI Zone Row
    chassis_bar = "█" * int(min(20, max(1, chassis_temp / 2.5)))
    chassis_style = "bold dark_goldenrod" if chassis_temp >= 38 else "bold dark_cyan"
    table.add_row("Chassis ACPI Zone", f"[{chassis_style}]{chassis_temp} °C[/{chassis_style}]", f"[{chassis_style}]{chassis_bar}[/{chassis_style}] [black](Airflow Soak Ceiling: 38°C)[/black]")

    # Thermal Delta Gradient
    gradient_str = f"[{'bold dark_green' if delta_t >= 8 else 'bold dark_red'}]{'EFFICIENT DISSIPATION' if delta_t >= 8 else 'SATURATED / STAGNANT'}[/]"
    table.add_row("Thermal Gradient (ΔT)", f"[bold dark_blue]{delta_t} °C[/bold dark_blue]", f"Die-to-Ambient: {gradient_str}")

    # CPU Power Limit Row
    cpu_bar = "█" * int(cpu / 5)
    table.add_row("CPU Power Throttle", f"[bold dark_cyan]{cpu} %[/bold dark_cyan]", f"[bold dark_cyan]{cpu_bar}[/bold dark_cyan] [black](Locked Ceiling: {ceiling}%)[/black]")

    # Governor State & Dwell
    dwell_str = f"{dwell}s remaining" if dwell > 0 else "Ready"
    table.add_row("Governor State", f"[bold dark_goldenrod]{state_tag}[/bold dark_goldenrod]", f"[black]Status: [bold]{status}[/bold] | Dwell: [bold dark_green]{dwell_str}[/bold dark_green] | Penalty: [bold dark_magenta]{penalty}s[/bold dark_magenta][/black]")

    layout["main"].update(Panel(table, title="[bold dark_blue]Real-Time Predictive Telemetry[/bold dark_blue]", border_style="dark_blue", box=box.ROUNDED))

    footer_text = Text(f"Controls: [7] Set 70% Max  |  [8] Set 80% Max  |  [Ctrl+C] Exit  |  {last_debug_err}", style="bold dark_blue")
    layout["footer"].update(Panel(footer_text, style="dark_blue", box=box.ROUNDED))

    return layout

def main():
    console.clear()
    with Live(generate_dashboard(None), refresh_per_second=2, console=console, screen=True) as live:
        try:
            while True:
                data = read_state()
                live.update(generate_dashboard(data))
                time.sleep(1)
        except KeyboardInterrupt:
            pass

if __name__ == "__main__":
    main()
