#!/usr/bin/env bash
# ==============================================================================
# run_test_vm.sh - Rescuezilla & Ventoy VM Test Harness & Emulation Lab
# ==============================================================================
# Features:
#   1. Boot Mode Selection:
#      - Option A: Full Ventoy Emulation via safe qcow2 copy-on-write overlay
#      - Option B: Direct Rescuezilla ISO Boot with persistent overlay
#   2. Display Interface Selection:
#      - Native GTK desktop window (direct X11 window on host)
#      - TigerVNC viewer (decoupled VNC client connecting to localhost:5901)
#   3. Safe Physical Partition Exposure (read-only):
#      - Optionally attach /dev/sda (or partitions) with readonly=on
#   4. SSH Port Forwarding:
#      - Maps host localhost:2222 -> VM guest port 22
# ==============================================================================
set -e

# Styling
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
DIM="\033[2m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_DEV="/dev/sdb"
ISO_PATH="/media/alan/Ventoy1/rescuezilla-2.6.1-64bit.oracular.iso"
PERSIST_IMG="/media/alan/Ventoy1/rescuezilla-persistence.dat"
VNC_PORT="5901"
SSH_PORT="2222"
RAM_SIZE="3072"
CPUS="2"

# Ensure root privileges for block device access
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo for KVM and block device access.${RESET}"
    echo "Usage: sudo $0"
    exit 1
fi

clear
echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       🧪 RESCUEZILLA & VENTOY VM TEST HARNESS & EMULATION LAB        ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

# 1. Select Boot Mode
echo -e "\n${BOLD}[1/3] Select Boot Pipeline Mode:${RESET}"
echo -e "${DIM}  ℹ️  Why choose: Option A tests full Ventoy MBR/GRUB menu handoff safely, while Option B boots the Rescuezilla desktop directly in seconds.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Option A: Full Ventoy Emulation (Safe CoW Snapshot of /dev/sdb)"
echo -e "  ${CYAN}[2]${RESET} Option B: Direct Rescuezilla ISO Boot (+ Persistence Overlay)"

while true; do
    echo -en "Select Boot Mode [1-2]: "
    read -r boot_choice
    case "$boot_choice" in
        1|2) break ;;
        *) echo -e "  ${YELLOW}Please enter 1 or 2.${RESET}" ;;
    esac
done

# 2. Select Display Interface
echo -e "\n${BOLD}[2/3] Select Display Interface:${RESET}"
echo -e "${DIM}  ℹ️  Why choose: Native GTK opens a regular window on your desktop. TigerVNC runs decoupled on localhost:${VNC_PORT} so you can close and reconnect the viewer without stopping the VM.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Native Window (Direct GTK X11 window on your desktop)"
echo -e "  ${CYAN}[2]${RESET} TigerVNC Viewer (Decoupled client connecting to localhost:${VNC_PORT})"

while true; do
    echo -en "Select Display Interface [1-2]: "
    read -r disp_choice
    case "$disp_choice" in
        1|2) break ;;
        *) echo -e "  ${YELLOW}Please enter 1 or 2.${RESET}" ;;
    esac
done

# 3. Safe Host Storage Passthrough (Read-Only)
echo -e "\n${BOLD}[3/3] Expose Host Storage for Real Backup Testing?${RESET}"
echo -e "${DIM}  ℹ️  Why choose: Exposing host partitions with kernel-enforced readonly=on allows Rescuezilla to create real Partclone backup images streaming over LAN to home40 without any danger of modifying host data.${RESET}"
echo -e "  ${CYAN}[1]${RESET} No: Isolated virtual sandbox (no host drives exposed)"
echo -e "  ${CYAN}[2]${RESET} Yes: Expose Internal Disk /dev/sda (Read-Only) for Real Backup Testing"
echo -e "  ${CYAN}[3]${RESET} Yes: Expose /dev/sda5 Linux Partition Only (Read-Only)"

while true; do
    echo -en "Select Storage Passthrough [1-3]: "
    read -r stor_choice
    case "$stor_choice" in
        1|2|3) break ;;
        *) echo -e "  ${YELLOW}Please enter 1, 2, or 3.${RESET}" ;;
    esac
done

# Telemetry Log Paths
VM_SERIAL_LOG="/tmp/vm_serial_console.log"
VM_QEMU_LOG="/tmp/qemu_rescuezilla_vm.log"
rm -f "$VM_SERIAL_LOG" "$VM_QEMU_LOG" 2>/dev/null || true
touch "$VM_SERIAL_LOG" "$VM_QEMU_LOG"
chmod 666 "$VM_SERIAL_LOG" "$VM_QEMU_LOG" 2>/dev/null || true

# Construct QEMU parameters
QEMU_ARGS=(
    -enable-kvm
    -cpu host
    -smp "$CPUS"
    -m "$RAM_SIZE"
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
    -serial "file:${VM_SERIAL_LOG}"
)

# Configure Storage & Boot drives
TEMP_COW="/tmp/ventoy_sdb_snapshot_$$.qcow2"
cleanup() {
    if [ -f "$TEMP_COW" ]; then
        echo -e "\n${DIM}Cleaning up transient CoW overlay: $TEMP_COW${RESET}"
        rm -f "$TEMP_COW" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if [ "$boot_choice" = "1" ]; then
    echo -e "\n[*] Initializing Option A: Creating transient CoW overlay for /dev/sdb..."
    qemu-img create -f qcow2 -b "$USB_DEV" -F raw "$TEMP_COW" >/dev/null
    QEMU_ARGS+=(
        -drive "file=${TEMP_COW},format=qcow2,if=virtio,cache=writeback"
        -boot c
    )
else
    echo -e "\n[*] Initializing Option B: Direct Rescuezilla ISO & Persistence boot..."
    if [ ! -f "$ISO_PATH" ]; then
        echo -e "${RED}Error: Rescuezilla ISO not found at $ISO_PATH${RESET}"
        exit 1
    fi
    BOOT_DIR="/media/alan/Ventoy1/boot_cache"
    if [ -f "${BOOT_DIR}/vmlinuz" ] && [ -f "${BOOT_DIR}/initrd.lz" ]; then
        echo -e "  • Using direct kernel launch with persistent overlay parameter..."
        QEMU_ARGS+=(
            -kernel "${BOOT_DIR}/vmlinuz"
            -initrd "${BOOT_DIR}/initrd.lz"
            -append "boot=casper persistent quiet splash ---"
            -cdrom "$ISO_PATH"
        )
    else
        QEMU_ARGS+=(
            -cdrom "$ISO_PATH"
            -boot d
        )
    fi
    if [ -f "$PERSIST_IMG" ]; then
        echo -e "  • Attaching persistence container: $PERSIST_IMG"
        QEMU_ARGS+=(
            -drive "file=${PERSIST_IMG},format=raw,if=virtio,cache=writeback"
        )
    fi
fi

# Configure Host Storage Passthrough (Read-Only)
case "$stor_choice" in
    2)
        if [ -b /dev/sda ]; then
            echo -e "  • Exposing /dev/sda (Read-Only) as virtual drive /dev/vdb..."
            QEMU_ARGS+=(-drive "file=/dev/sda,format=raw,if=virtio,readonly=on")
        else
            echo -e "${YELLOW}Warning: /dev/sda not found. Skipping passthrough.${RESET}"
        fi
        ;;
    3)
        if [ -b /dev/sda5 ]; then
            echo -e "  • Exposing /dev/sda5 (Read-Only) as virtual drive /dev/vdb..."
            QEMU_ARGS+=(-drive "file=/dev/sda5,format=raw,if=virtio,readonly=on")
        else
            echo -e "${YELLOW}Warning: /dev/sda5 not found. Skipping passthrough.${RESET}"
        fi
        ;;
    *)
        echo -e "  • Operating in isolated sandbox mode."
        ;;
esac

# Configure Display
if [ "$disp_choice" = "1" ]; then
    echo -e "\n[+] Launching QEMU with Native GTK Window..."
    # Ensure X11 display permissions if run under sudo
    export DISPLAY="${DISPLAY:-:1}"
    export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"
    QEMU_ARGS+=(-display gtk)
    
    echo -e "${GREEN}======================================================================${RESET}"
    echo -e "${GREEN}✓ VM Starting!${RESET}"
    echo -e "  • Display: Native GTK Window (Press Ctrl+Alt+G to release mouse)"
    echo -e "  • SSH Port: localhost:${SSH_PORT} (Connect via: ssh -p ${SSH_PORT} ubuntu@localhost)"
    echo -e "  • Serial Log: ${VM_SERIAL_LOG}"
    echo -e "  • QEMU Log:   ${VM_QEMU_LOG}"
    echo -e "${GREEN}======================================================================${RESET}"
    qemu-system-x86_64 "${QEMU_ARGS[@]}" 2>>"$VM_QEMU_LOG"
else
    echo -e "\n[+] Launching QEMU with TigerVNC Server on localhost:${VNC_PORT}..."
    QEMU_ARGS+=(
        -vnc "127.0.0.1:1"
    )
    
    qemu-system-x86_64 "${QEMU_ARGS[@]}" 2>>"$VM_QEMU_LOG" &
    VM_PID=$!
    
    sleep 1
    echo -e "${GREEN}======================================================================${RESET}"
    echo -e "${GREEN}✓ VM Running in Background (PID: ${VM_PID})!${RESET}"
    echo -e "  • VNC Server: localhost:${VNC_PORT}"
    echo -e "  • SSH Port: localhost:${SSH_PORT} (Connect via: ssh -p ${SSH_PORT} ubuntu@localhost)"
    echo -e "  • Serial Log: ${VM_SERIAL_LOG}"
    echo -e "  • QEMU Log:   ${VM_QEMU_LOG}"
    echo -e "${GREEN}======================================================================${RESET}"
    
    echo -e "[*] Spawning TigerVNC Viewer..."
    export DISPLAY="${DISPLAY:-:1}"
    export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"
    vncviewer "localhost:${VNC_PORT}" 2>/dev/null || xtigervncviewer "localhost:${VNC_PORT}" 2>/dev/null || true
    
    wait $VM_PID 2>/dev/null || true
fi
