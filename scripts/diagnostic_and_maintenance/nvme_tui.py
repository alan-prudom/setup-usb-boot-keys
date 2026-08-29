# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "rich",
#     "textual",
# ]
# ///

import os
import json
import time
from datetime import datetime
from rich.console import Console
from rich.panel import Panel
from rich.layout import Layout
from rich.table import Table
from rich.text import Text
from rich.live import Live

STATE_FILE = r"D:\nvme_state.json"
CONTROL_FILE = r"D:\nvme_control.json"

console = Console()

def read_state():
    if not os.path.exists(STATE_FILE):
        return None
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
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
        Layout(name="main", size=12),
        Layout(name="footer", size=3)
    )

    # Header
    header_text = Text("🛡️  Dual-Sensor Predictive NVMe Thermal Governor & Monitor", style="bold cyan")
    header_panel = Panel(header_text, style="cyan", subtitle=datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    layout["header"].update(header_panel)

    if not data:
        layout["main"].update(Panel("[yellow]Waiting for Daemon State Snapshot (D:\\nvme_state.json)...[/yellow]", title="State"))
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

    # NVMe Temp Color
    if nvme_temp >= 57:
        nvme_style = "bold red"
    elif nvme_temp >= 55:
        nvme_style = "bold magenta"
    elif nvme_temp >= 51:
        nvme_style = "bold yellow"
    else:
        nvme_style = "bold green"

    # Main Grid
    table = Table(expand=True, box=None)
    table.add_column("Sensor / Domain", justify="left", style="bold white")
    table.add_column("Reading", justify="center")
    table.add_column("Thermal Trajectory & Status Bar", justify="left")

    # NVMe Controller Die Row
    nvme_bar = "█" * int(min(20, max(1, (nvme_temp - 30) / 1.5)))
    table.add_row("🌡️ NVMe Controller Die", f"[{nvme_style}]{nvme_temp} °C[/{nvme_style}]", f"[{nvme_style}]{nvme_bar}[/{nvme_style}] (Limit: 55°C)")

    # Chassis ACPI Zone Row
    chassis_bar = "█" * int(min(20, max(1, chassis_temp / 2.5)))
    chassis_style = "bold yellow" if chassis_temp >= 38 else "bold blue"
    table.add_row("🌀 Chassis ACPI Zone", f"[{chassis_style}]{chassis_temp} °C[/{chassis_style}]", f"[{chassis_style}]{chassis_bar}[/{chassis_style}] (Heat Soak Ceiling: 38°C)")

    # Thermal Delta Gradient
    table.add_row("📐 Thermal Gradient (ΔT)", f"[bold cyan]{delta_t} °C[/bold cyan]", f"Die-to-Ambient Dissipation: [green]{'EFFICIENT' if delta_t >= 8 else 'SATURATED'}[/green]")

    # CPU Power Limit Row
    cpu_bar = "█" * int(cpu / 5)
    table.add_row("⚡ CPU Power Throttle", f"[bold cyan]{cpu} %[/bold cyan]", f"[cyan]{cpu_bar}[/cyan] (Max: {ceiling}%)")

    # Governor State & Dwell
    dwell_str = f"{dwell}s remaining" if dwell > 0 else "Ready"
    table.add_row("🏷️ Governor State", f"[bold yellow]{state_tag}[/bold yellow]", f"Status: [white]{status}[/white] | Dwell: [green]{dwell_str}[/green] | Penalty: [magenta]{penalty}s[/magenta]")

    layout["main"].update(Panel(table, title="[bold]Real-Time Predictive Telemetry[/bold]", border_style="blue"))

    # Footer Controls
    footer_text = Text("Controls: [7] Set 70% Max  |  [8] Set 80% Max  |  [9] Set 90% Max  |  [Ctrl+C] Exit", style="dim")
    layout["footer"].update(Panel(footer_text, style="dim"))

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
