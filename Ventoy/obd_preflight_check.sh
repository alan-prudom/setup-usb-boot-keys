#!/usr/bin/env bash
# ==============================================================================
# obd_preflight_check.sh
# On-Board Diagnostics (OBD) & Pre-Flight System Verification
# Runs in live USB (or host) to inspect modules, storage, services, and runtimes.
# ==============================================================================
set -u

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
DIM="\033[2m"
RESET="\033[0m"

PASS_CNT=0
WARN_CNT=0
FAIL_CNT=0

check_status() {
    local status="$1"
    local name="$2"
    local details="$3"

    case "$status" in
        PASS)
            echo -e "  [${GREEN}PASS${RESET}] ${BOLD}${name}${RESET}: ${details}"
            PASS_CNT=$((PASS_CNT + 1))
            ;;
        WARN)
            echo -e "  [${YELLOW}WARN${RESET}] ${BOLD}${name}${RESET}: ${details}"
            WARN_CNT=$((WARN_CNT + 1))
            ;;
        FAIL)
            echo -e "  [${RED}FAIL${RESET}] ${BOLD}${name}${RESET}: ${details}"
            FAIL_CNT=$((FAIL_CNT + 1))
            ;;
    esac
}

echo "======================================================================"
echo -e "${BOLD}         🩺 ON-BOARD DIAGNOSTICS (OBD) & PRE-FLIGHT CHECK             ${RESET}"
echo "======================================================================"
echo "Host / System  : $(uname -n) ($(uname -r) $(uname -m))"
echo "Timestamp      : $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================================"

echo -e "\n${BOLD}[1/5] Kernel Modules & Drivers${RESET}"
# 1. NBD module
if lsmod | grep -q "^nbd "; then
    check_status PASS "nbd kernel module" "Loaded and active"
else
    if modprobe nbd 2>/dev/null; then
        check_status PASS "nbd kernel module" "Successfully auto-loaded"
    else
        check_status WARN "nbd kernel module" "Not loaded (modprobe failed or missing in /lib/modules)"
    fi
fi

# 2. Fuse module
if lsmod | grep -q "^fuse "; then
    check_status PASS "fuse module" "Loaded (required for SSHFS & NTFS-3G)"
else
    modprobe fuse 2>/dev/null && check_status PASS "fuse module" "Auto-loaded" || check_status WARN "fuse module" "Not loaded"
fi

# 3. Overlayfs
if lsmod | grep -q "^overlay " || grep -q "overlay" /proc/filesystems; then
    check_status PASS "overlay filesystem" "Active (Casper live persistence supported)"
else
    check_status WARN "overlay filesystem" "Not detected in active modules"
fi

echo -e "\n${BOLD}[2/5] Storage & Persistence Volumes${RESET}"
# 1. Casper persistence (/cow)
if grep -q " /cow " /proc/mounts || grep -q " /casper-rw " /proc/mounts || [ -d "/upper" ]; then
    check_status PASS "Persistence overlay" "Active write-layer mounted"
else
    check_status WARN "Persistence overlay" "Volatile / RAM mode detected (persistence container not active)"
fi

# 2. Partition 4 Storage (/home/ubuntu/ntfs_usb or /media/devmon/*)
P4_FOUND=""
for p4_cand in "/home/ubuntu/ntfs_usb" "/media/ubuntu/2C95D29B2DF0500E" "/media/ubuntu/SHARED_FAT" "/media/devmon/sdb4-usb-Generic-_SD_MMC_"; do
    if [ -d "$p4_cand" ] && [ -w "$p4_cand" ]; then
        P4_FOUND="$p4_cand"
        break
    fi
done

if [ -n "$P4_FOUND" ]; then
    free_mb=$(df -BM "$P4_FOUND" | tail -n1 | awk '{print $4}' | tr -d 'M')
    check_status PASS "Partition 4 Storage" "Accessible at ${P4_FOUND} (${free_mb}MB free)"
else
    check_status WARN "Partition 4 Storage" "Not mounted or read-only (coverage traces may save to /tmp)"
fi

echo -e "\n${BOLD}[3/5] Network & Remote SSH Services${RESET}"
# 1. SSH Server Daemon
if pgrep -x sshd >/dev/null 2>&1; then
    check_status PASS "OpenSSH Server" "sshd daemon running (PID $(pgrep -x sshd | head -n1))"
else
    check_status WARN "OpenSSH Server" "sshd daemon not running"
fi

# 2. Port 22 listening
if command -v ss >/dev/null 2>&1; then
    if ss -tlpn | grep -q ":22 "; then
        check_status PASS "SSH Port 22" "Listening for incoming connections"
    else
        check_status WARN "SSH Port 22" "Port 22 not listening"
    fi
fi

# 3. SSHFS Client
if command -v sshfs >/dev/null 2>&1; then
    check_status PASS "sshfs utility" "Present ($(sshfs --version 2>&1 | head -n1))"
else
    check_status FAIL "sshfs utility" "Missing (remote LAN backup requires sshfs)"
fi

# 4. Identity Key
if [ -f "/scripts/id_rsa" ] || [ -f "$HOME/.ssh/id_rsa" ]; then
    check_status PASS "SSH Identity Key" "id_rsa key present"
else
    check_status WARN "SSH Identity Key" "id_rsa not found in standard paths"
fi

echo -e "\n${BOLD}[4/5] Runtimes & Test Tooling${RESET}"
# Python
if command -v python3 >/dev/null 2>&1; then
    check_status PASS "Python runtime" "$(python3 --version)"
else
    check_status FAIL "Python runtime" "python3 not found"
fi

# UV
if command -v uv >/dev/null 2>&1; then
    check_status PASS "uv package manager" "$(uv --version)"
elif [ -x "/home/ubuntu/ntfs_usb/bin/uv" ] || [ -x "/media/devmon/sdb4-usb-Generic-_SD_MMC_/bin/uv" ]; then
    check_status PASS "uv package manager" "Found on Partition 4 (/bin/uv)"
else
    check_status WARN "uv package manager" "uv not found (system will fall back to python3)"
fi

# Expect
if command -v expect >/dev/null 2>&1; then
    check_status PASS "expect automation" "Installed and executable"
else
    check_status WARN "expect automation" "Not installed (automated expect tests disabled; manual coverage works)"
fi

# LCOV
if command -v lcov >/dev/null 2>&1; then
    check_status PASS "lcov utility" "Installed ($(lcov --version 2>&1 | head -n1))"
else
    check_status WARN "lcov utility" "lcov not installed (trace-to-lcov parser will generate .info file directly)"
fi

echo -e "\n${BOLD}[5/5] Desktop & Display Status${RESET}"
# 1. UsrMerge Integrity Check
if [ -L "/lib" ] && [ "$(readlink -f /lib)" = "/usr/lib" ]; then
    check_status PASS "UsrMerge Integrity" "/lib correctly symlinked to /usr/lib"
elif [ -d "/lib" ] && [ ! -L "/lib" ]; then
    check_status FAIL "UsrMerge Integrity" "/lib is a physical directory (OverlayFS masking /usr/lib base!)"
else
    check_status PASS "UsrMerge Integrity" "Filesystem layout verified"
fi

# 2. Display Manager Target Resolution
if [ -L "/etc/systemd/system/display-manager.service" ]; then
    dm_target=$(readlink -f "/etc/systemd/system/display-manager.service" 2>/dev/null || true)
    if [ -f "$dm_target" ]; then
        check_status PASS "Display Manager Target" "Resolves cleanly to $dm_target"
    else
        check_status FAIL "Display Manager Target" "Broken symlink! Target does not exist: $(readlink /etc/systemd/system/display-manager.service 2>/dev/null)"
    fi
fi

# 3. LightDM Active State
if systemctl is-active lightdm >/dev/null 2>&1; then
    check_status PASS "LightDM Display Manager" "Active and running"
elif command -v lightdm >/dev/null 2>&1; then
    check_status WARN "LightDM Display Manager" "Inactive (desktop GUI waiting to start)"
fi

# 4. Failed Services Audit
if command -v systemctl >/dev/null 2>&1; then
    failed_units=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | xargs || true)
    if [ -z "$failed_units" ]; then
        check_status PASS "System Services Health" "Zero failed systemd units"
    else
        check_status WARN "System Services Health" "Failed units detected: ${failed_units}"
    fi
fi

# 5. Current Display Variable
if [ -n "${DISPLAY:-}" ]; then
    check_status PASS "X11 Display" "DISPLAY is set to $DISPLAY"
else
    check_status WARN "X11 Display" "DISPLAY environment variable not set in current shell"
fi

echo -e "\n======================================================================"
echo -e "${BOLD}OBD Diagnostics Summary:${RESET} ${GREEN}${PASS_CNT} Passed${RESET}, ${YELLOW}${WARN_CNT} Warnings${RESET}, ${RED}${FAIL_CNT} Failures${RESET}"
echo "======================================================================"

if [ "$FAIL_CNT" -eq 0 ]; then
    echo -e "${GREEN}✓ System is PRE-FLIGHT READY for Backup & Coverage Testing.${RESET}\n"
    exit 0
else
    echo -e "${RED}⚠️  Critical pre-flight checks failed. Please address before backup.${RESET}\n"
    exit 1
fi
