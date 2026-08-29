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
        Layout(name="main", size=10),
        Layout(name="footer", size=3)
    )

    # Header
    header_text = Text("🛡️  NVMe Proportional Thermal Governor & Live Monitor", style="bold cyan")
    header_panel = Panel(header_text, style="cyan", subtitle=datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    layout["header"].update(header_panel)

    if not data:
        layout["main"].update(Panel("[yellow]Waiting for Daemon State Snapshot (D:\\nvme_state.json)...[/yellow]", title="State"))
        return layout

    temp = data.get("temperatureC", 0)
    cpu = data.get("cpuLimitPercent", 0)
    ceiling = data.get("maxCeiling", 75)
    state_tag = data.get("stateTag", "N/A")
    dwell = data.get("dwellRemaining", 0)
    penalty = data.get("probePenaltyRemaining", 0)
    status = data.get("status", "N/A")

    # Temp Color
    if temp >= 57:
        temp_style = "bold red"
    elif temp >= 55:
        temp_style = "bold magenta"
    elif temp >= 51:
        temp_style = "bold yellow"
    else:
        temp_style = "bold green"

    # Main Grid
    table = Table(expand=True, box=None)
    table.add_column("Sensor / Metric", justify="left", style="bold white")
    table.add_column("Value", justify="center")
    table.add_column("Progress / Threshold Bar", justify="left")

    # Temp Row
    temp_bar = "█" * int(min(20, max(1, (temp - 30) / 2)))
    table.add_row("🌡️ NVMe Temperature", f"[{temp_style}]{temp} °C[/{temp_style}]", f"[{temp_style}]{temp_bar}[/{temp_style}] (Limit: 55°C)")

    # CPU Power Limit Row
    cpu_bar = "█" * int(cpu / 5)
    table.add_row("⚡ CPU Power Throttle", f"[bold cyan]{cpu} %[/bold cyan]", f"[cyan]{cpu_bar}[/cyan] (Max: {ceiling}%)")

    # Governor State
    table.add_row("🏷️ Governor State", f"[bold yellow]{state_tag}[/bold yellow]", f"Status: [white]{status}[/white]")

    # Dwell / Penalty Timers
    dwell_str = f"{dwell}s remaining" if dwell > 0 else "Ready"
    table.add_row("⏱️ Stability Dwell", f"[green]{dwell_str}[/green]", f"Probe Penalty Cooldown: [magenta]{penalty}s[/magenta]")

    layout["main"].update(Panel(table, title="[bold]Real-Time Telemetry[/bold]", border_style="blue"))

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
