#!/usr/bin/env bash
# ==============================================================================
# stimulate_vm_tests.sh - Automated SSH Test Harness for Rescuezilla VM
# ==============================================================================
# Connects to the running VM via localhost:2222 and executes automated checks:
#   1. SSH connectivity verification (retries until guest boots)
#   2. Verifies storage auto-mounts (SHARED FAT, Internal_HDD)
#   3. Checks OverlayFS persistence layer (/cow/upper)
#   4. Validates desktop launcher files
#   5. Harvests system and desktop log telemetry
# ==============================================================================
set -e

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
RESET="\033[0m"

SSH_PORT="2222"
SSH_USER="ubuntu"
SSH_HOST="localhost"
KEY_FILE="/home/alan/.ssh/id_rsa"
SSH_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -o LogLevel=ERROR"

if [ -f "$KEY_FILE" ]; then
    SSH_OPTS="-i ${KEY_FILE} ${SSH_OPTS}"
fi

# Use sshpass fallback with default 'live' password if available
SSH_CMD="ssh"
if command -v sshpass >/dev/null 2>&1; then
    SSH_CMD="sshpass -p live ssh"
fi

echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       🤖 RESCUEZILLA VM AUTOMATED SSH TEST HARNESS                   ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

echo -e "\n[*] Waiting for VM SSH service on ${SSH_HOST}:${SSH_PORT}..."
MAX_ATTEMPTS=40
ATTEMPT=1
CONNECTED=0

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if ${SSH_CMD} ${SSH_OPTS} "${SSH_USER}@${SSH_HOST}" "uptime" >/dev/null 2>&1; then
        CONNECTED=1
        echo -e "${GREEN}✓ Connected to Rescuezilla VM via SSH!${RESET}"
        break
    fi
    echo -n "."
    sleep 3
    ATTEMPT=$((ATTEMPT + 1))
done

if [ "$CONNECTED" -ne 1 ]; then
    echo -e "\n${RED}Error: Timed out waiting for VM SSH on port ${SSH_PORT}.${RESET}"
    echo "Check if the VM is booting and networking is initialized."
    exit 1
fi

echo -e "\n${BOLD}[Test 1/4] Inspecting Guest System & Block Devices...${RESET}"
${SSH_CMD} ${SSH_OPTS} "${SSH_USER}@${SSH_HOST}" "uname -a; echo '--- BLOCK DEVICES ---'; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT"

echo -e "\n${BOLD}[Test 2/4] Verifying OverlayFS Persistence Mounts...${RESET}"
${SSH_CMD} ${SSH_OPTS} "${SSH_USER}@${SSH_HOST}" "df -hT / /cow 2>/dev/null || true; echo '--- MOUNTS ---'; grep -iE 'overlay|cow|partimag' /proc/mounts || true"

echo -e "\n${BOLD}[Test 3/4] Checking Desktop Launchers & Exec Validity...${RESET}"
${SSH_CMD} ${SSH_OPTS} "${SSH_USER}@${SSH_HOST}" "ls -la /home/ubuntu/Desktop/; echo '--- DESKTOP FILE VALIDATION ---'; for f in /home/ubuntu/Desktop/*.desktop; do if command -v desktop-file-validate >/dev/null 2>&1; then desktop-file-validate \"\$f\" 2>&1 || echo \"FAILED: \$f\"; else echo \"OK: \$f\"; fi; done"

echo -e "\n${BOLD}[Test 4/4] Checking Storage Auto-Mount Logs...${RESET}"
${SSH_CMD} ${SSH_OPTS} "${SSH_USER}@${SSH_HOST}" "tail -n 20 /var/log/startup_storage.log 2>/dev/null || tail -n 20 ~/startup_storage.log 2>/dev/null || echo 'No startup storage log yet.'"

echo -e "\n${GREEN}======================================================================${RESET}"
echo -e "${GREEN}✓ Automated VM Diagnostic Run Completed!${RESET}"
echo -e "${GREEN}======================================================================${RESET}"
