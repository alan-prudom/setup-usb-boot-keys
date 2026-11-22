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
if [ -f "${SCRIPT_DIR}/lib/lib_hardware_detect.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/lib/lib_hardware_detect.sh"
fi

USB_DEV="$(detect_usb_device 2>/dev/null || echo "/dev/sdb")"

# Dynamic ISO Discovery
ISO_PATH=""
for iso_cand in \
    "/media/devmon/sdb4-usb-Generic-_SD_MMC_/Ventoy images/rescuezilla-2.6.1-64bit.oracular.iso" \
    "/media/devmon/Ventoy/rescuezilla-2.6.2-64bit.noble.iso" \
    "/media/devmon/Ventoy/rescuezilla-2.6.1-64bit.oracular.iso" \
    "/media/alan/Ventoy1/rescuezilla-2.6.1-64bit.oracular.iso" \
    "/media/alan/Ventoy/rescuezilla-2.6.2-64bit.noble.iso"; do
    if [ -f "$iso_cand" ]; then
        ISO_PATH="$iso_cand"
        break
    fi
done

# Dynamic Persistence Discovery
PERSIST_IMG=""
for dat_cand in \
    "/media/devmon/Ventoy/rescuezilla-persistence.dat" \
    "/media/alan/Ventoy1/rescuezilla-persistence.dat" \
    "/media/alan/Ventoy/rescuezilla-persistence.dat" \
    "${SCRIPT_DIR}/rescuezilla-persistence.dat"; do
    if [ -f "$dat_cand" ]; then
        PERSIST_IMG="$dat_cand"
        break
    fi
done

VNC_PORT="5901"
SSH_PORT="2222"
RAM_SIZE="3072"
CPUS="2"


# Ensure root privileges for block device access
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run with sudo for KVM and block device access.${RESET}"
    echo "Usage: sudo $0 [--boot 1|2] [--display 1|2] [--storage 1|2|3] [--help]"
    exit 1
fi

boot_choice=""
disp_choice=""
stor_choice=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot)
            boot_choice="$2"
            shift 2
            ;;
        --display)
            disp_choice="$2"
            shift 2
            ;;
        --storage)
            stor_choice="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: sudo $0 [OPTIONS]"
            echo "Options:"
            echo "  --boot 1|2       1: Full Ventoy CoW, 2: Direct Rescuezilla ISO"
            echo "  --display 1|2    1: Native GTK window, 2: TigerVNC Server"
            echo "  --storage 1|2|3  1: Sandbox, 2: Expose /dev/sda (RO), 3: Expose /dev/sda5 (RO)"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

clear 2>/dev/null || true
echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       🧪 RESCUEZILLA & VENTOY VM TEST HARNESS & EMULATION LAB        ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

# 1. Select Boot Mode
if [ -z "$boot_choice" ]; then
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
fi

# 2. Select Display Interface
if [ -z "$disp_choice" ]; then
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
fi

# 3. Safe Host Storage Passthrough (Read-Only)
if [ -z "$stor_choice" ]; then
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
fi

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
    -global "isa-fdc.fdtypeA=none"
    -global "isa-fdc.fdtypeB=none"
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
    echo -e "\n[*] Flushing kernel disk buffers before snapshot..."
    sync
    echo -e "[*] Initializing Option A: Creating transient CoW overlay for ${USB_DEV}..."
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
    BOOT_DIR="/media/devmon/Ventoy/boot_cache"
    if [ ! -d "$BOOT_DIR" ]; then
        for cand_dir in "/media/alan/Ventoy1/boot_cache" "/media/alan/Ventoy/boot_cache" "${SCRIPT_DIR}/boot_cache"; do
            if [ -d "$cand_dir" ]; then
                BOOT_DIR="$cand_dir"
                break
            fi
        done
    fi
    if [ -f "${BOOT_DIR}/vmlinuz" ] && [ -f "${BOOT_DIR}/initrd.lz" ]; then
        echo -e "  • Using direct kernel launch with persistent overlay parameter..."
        QEMU_ARGS+=(
            -kernel "${BOOT_DIR}/vmlinuz"
            -initrd "${BOOT_DIR}/initrd.lz"
            -append "boot=casper persistent noprompt console=ttyS0 console=tty1 quiet splash ---"
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
HOST_USER="${SUDO_USER:-$USER}"
HOST_UID=$(id -u "$HOST_USER" 2>/dev/null || echo "1000")

# Ensure DISPLAY is set
export DISPLAY="${DISPLAY:-:0}"

# Auto-detect Xauthority for Wayland / X11
if [ -z "${XAUTHORITY:-}" ] || [ ! -f "$XAUTHORITY" ]; then
    AUTH_CAND=$(ls /run/user/"$HOST_UID"/.mutter-Xwaylandauth.* /run/user/"$HOST_UID"/gdm/Xauthority /home/"$HOST_USER"/.Xauthority 2>/dev/null | head -n 1)
    if [ -n "$AUTH_CAND" ] && [ -f "$AUTH_CAND" ]; then
        export XAUTHORITY="$AUTH_CAND"
    fi
fi

# Authorize root on host display if run via sudo
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" DISPLAY="$DISPLAY" xhost +si:localuser:root >/dev/null 2>&1 || true
fi

if [ "$disp_choice" = "1" ]; then
    echo -e "\n[+] Launching QEMU with Native GTK Window..."
    QEMU_ARGS+=(-display gtk)
    
    echo -e "${GREEN}======================================================================${RESET}"
    echo -e "${GREEN}✓ VM Starting!${RESET}"
    echo -e "  • Display: Native GTK Window (Press Ctrl+Alt+G to release mouse)"
    echo -e "  • SSH Port: localhost:${SSH_PORT} (Connect via: ssh -p ${SSH_PORT} ubuntu@localhost)"
    echo -e "  • Serial Log: ${VM_SERIAL_LOG}"
    echo -e "  • QEMU Log:   ${VM_QEMU_LOG}"
    echo -e "${GREEN}======================================================================${RESET}"
    if ! qemu-system-x86_64 "${QEMU_ARGS[@]}" 2>>"$VM_QEMU_LOG"; then
        echo -e "${RED}✗ Error: QEMU terminated with an error.${RESET}"
        echo -e "${YELLOW}--- QEMU Log (/tmp/qemu_rescuezilla_vm.log) ---${RESET}"
        cat "$VM_QEMU_LOG"
        echo -e "${YELLOW}-----------------------------------------------${RESET}"
    fi
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
    
    # Try spawning viewer if DISPLAY is accessible
    if [ -n "$DISPLAY" ]; then
        echo -e "[*] Spawning TigerVNC Viewer (Auto-Fit & Dynamic Rescaling enabled)..."
        echo -e "${DIM}  ℹ️  Tip: Press F8 in the TigerVNC window to toggle Full Screen or access Options.${RESET}"
        vncviewer -RemoteResize=1 "localhost:${VNC_PORT}" 2>/dev/null || xtigervncviewer -RemoteResize=1 "localhost:${VNC_PORT}" 2>/dev/null || true &
    fi
    
    wait $VM_PID 2>/dev/null || true
fi
