# Disk Management & Automation Strategy (19GB Partition)

This document outlines the automated cleanup and monitoring implemented to stabilize a 19GB root partition.

## 1. Automated Cleanup (`/usr/local/bin/auto-clean.sh`)
**Schedule:** Every Sunday at 3:00 AM (`crontab`).
*   **APT:** Cleans package cache (`apt-get clean`) and removes orphans (`autoremove`).
*   **Journald:** Vacuums logs to **50MB**.
*   **Snaps:** Purges old/disabled revisions.
*   **Docker:** (Optional) Prunes build caches.

## 2. Real-Time Alerting (`/usr/local/bin/disk-alert.sh`)
**Schedule:** Hourly (`crontab`).
*   **Threshold:** Triggers at **90%** usage.
*   **Notification:** Logs a critical alert to `journalctl -t disk-alert -p crit`.
*   **Expandability:** Includes placeholder for Discord/Slack webhooks.

## 3. System Configuration Changes
*   **Snap Retention:** Set to **2** (`snap set system refresh.retain=2`).
*   **Journal Cap:** Set to **50MB** in `/etc/systemd/journald.conf`.

## 4. Diagnostic Tools
Added a `ghosts` alias to `.bashrc`:
*   **Command:** `ghosts`
*   **Usage:** `sudo lsof / | grep deleted`
*   **Purpose:** Identify processes holding deleted files.

## 5. Potential Future Actions
Identified ~1.5GB of reclaimable space in `/home/alan/`:
*   `.nvm` & `.npm` (Node.js caches)
*   `.cache` (Browser artifacts)
*   `.antigravity-server` (Application data)
