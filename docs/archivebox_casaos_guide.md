# ArchiveBox & CasaOS Management Guide

This document summarizes the findings regarding the ArchiveBox configurations on your system and provides instructions on how CasaOS manages Docker services, including how to update and execute commands.

---

## 📊 Findings Summary

Our investigation located two separate instances of the ArchiveBox `docker-compose.yml` configuration:

| Type | Path | Purpose | Tag |
| :--- | :--- | :--- | :--- |
| **Active Production** | `/var/lib/casaos/apps/archivebox/docker-compose.yml` | The live container setup managed by CasaOS. | `0.7.3` |
| **Backup / Git Repo** | `/home/alan/Github/setup-usb-boot-keys/docker-compose.yml` | Stored in your local setup repository. | `0.7.3` |

> [!NOTE]
> The active Docker containers (`archivebox` and `archivebox_scheduler`) are running from the CasaOS production path.

---

## ☁️ What is CasaOS?

**CasaOS** is an open-source personal cloud platform designed to simplify self-hosting. It acts as an elegant GUI dashboard built on top of Docker and Docker Compose. 

### How CasaOS Manages Apps:
1. **Application Directories**: Every app installed via CasaOS gets its own directory under `/var/lib/casaos/apps/<app-name>/`.
2. **Lifecycle Management**: CasaOS reads the `docker-compose.yml` file in that directory to start, stop, monitor, and update the containers.
3. **Data Storage**: App data is typically bind-mounted to the host system under `/DATA/AppData/<app-name>/` (or as defined in the compose volumes). For your ArchiveBox instance, the data is saved at:
   `/DATA/AppData/archivebox/data/`

---

## ⚙️ How to Update ArchiveBox in CasaOS

Since CasaOS is running the container, you have two ways to update it to the new stable version (`0.7.4`).

### Option 1: Via the CasaOS Web UI (Recommended)
1. Open your CasaOS web dashboard in your browser.
2. Hover over the **ArchiveBox** app icon and click the **three dots (`...`)** in the top-right corner.
3. Click **Settings**.
4. In the **Image** field, change:
   `archivebox/archivebox:0.7.3` ➔ `archivebox/archivebox:0.7.4`
5. Click **Save**. CasaOS will automatically pull the new image and recreate the containers for you.

### Option 2: Via the Terminal (Command Line)
If you prefer using the terminal, run the following commands:

```bash
# 1. Edit the compose file using sudo
sudo nano /var/lib/casaos/apps/archivebox/docker-compose.yml

# 2. Change the image tag on lines 34 and 367:
#    image: archivebox/archivebox:0.7.3  ➔  image: archivebox/archivebox:0.7.4

# 3. Navigate to the app directory
cd /var/lib/casaos/apps/archivebox/

# 4. Pull the new version of the image
sudo docker compose pull

# 5. Recreate and restart the containers in the background
sudo docker compose up -d --remove-orphans
```

---

## 🛠️ How to Run ArchiveBox Commands

Since ArchiveBox is running inside a Docker container, you cannot run `archivebox` directly on your host machine. Instead, you must execute commands *inside* the running container.

### Basic Container Management

* **Check container logs**:
  ```bash
  sudo docker logs -f archivebox
  ```
* **Restart the services**:
  ```bash
  sudo docker restart archivebox archivebox_scheduler
  ```

### ArchiveBox CLI Interactions

Use `docker exec` to run commands inside the active `archivebox` container:

* **Add a URL to your archive**:
  ```bash
  sudo docker exec -it archivebox archivebox add "https://example.com"
  ```
* **Check ArchiveBox status / configuration**:
  ```bash
  sudo docker exec -it archivebox archivebox status
  ```
* **List all archived pages**:
  ```bash
  sudo docker exec -it archivebox archivebox list
  ```
* **Re-run setup/init within the container**:
  ```bash
  sudo docker exec -it archivebox archivebox init
  ```
