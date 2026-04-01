# Headless Server & USB Boot Setup Guide

This guide covers essential post-installation steps for configuring a headless Linux machine (such as a device running from a Ventoy USB boot). It details how to set up remote desktop access via TigerVNC, prepare a modern Node.js environment via NVM, and handle headless authentication workflows.

---

## 1. Setting Up TigerVNC with XFCE (Fixing Wayland Crashes)

By default, modern Ubuntu and XFCE environments attempt to initialize a Wayland display (`wayland-0`). When running inside a TigerVNC session, this causes the desktop environment to instantly crash and shut down the VNC server, resulting in a "Connection Refused" error for clients. 

To fix this, we must configure VNC to aggressively clear Wayland variables and force a standard X11 session.

### Installation

1. Install the VNC server and the lightweight XFCE desktop environment:
   ```bash
   sudo apt update
   sudo apt install tigervnc-standalone-server xfce4 xfce4-goodies
   ```

2. Generate your VNC password. This password will be required when connecting from your VNC Viewer:
   ```bash
   vncpasswd
   ```

### Configuration: The `xstartup` Script

Create or edit the VNC startup script at `~/.vnc/xstartup`. **This is the exact script required to bypass the Wayland crashes:**

```bash
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Aggressively unset Wayland to prevent XFCE from crashing the VNC server
unset WAYLAND_DISPLAY
export WAYLAND_DISPLAY=

# Read X11 resources if present
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
xsetroot -solid grey

# Force initialization using dbus-launch and an isolated xfce4-session
exec dbus-launch xfce4-session
```

Make the script executable:
```bash
chmod +x ~/.vnc/xstartup
```

### Running and Managing the Server

**Option A: Local Network Access (Less Secure)**
If you are on a trusted local network and want to connect directly to the machine's IP address (e.g., `192.168.1.100:5902`), start the server and allow external connections:
```bash
vncserver :2 -localhost no
```

**Option B: SSH Tunneling (More Secure, Recommended)**
If you are accessing the machine over the internet, keep it bound to localhost:
```bash
vncserver :2
```
Then, on your local laptop, tunnel port `5902` through SSH:
```bash
ssh -L 5902:localhost:5902 alan@<remote-ip>
```
You can then open your VNC Viewer and connect to `localhost:5902`.

To kill the server when you are done:
```bash
vncserver -kill :2
```

---

## 2. Using NVM to Install Node.js & CLI Tools

When working on a headless Linux machine, you should avoid installing Node.js via the default `apt` package manager. `apt` usually installs outdated versions of Node, and installing global NPM packages requires `sudo`, which frequently breaks permissions. Instead, use Node Version Manager (`nvm`).

### Installing NVM

1. Download and run the NVM installer:
   ```bash
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
   ```
2. Reload your terminal profile to make the `nvm` command available:
   ```bash
   source ~/.bashrc
   ```

### Installing Node and Global CLIs

Install the current Long Term Support (LTS) version of Node.js:
```bash
nvm install --lts
nvm use --lts
```

Because NVM handles Node in your user directory, you can now safely install global CLI tools (like `gemini-cli`) without ever needing root access:
```bash
npm install -g gemini-cli
```

---

## 3. Authenticating on a Headless SSH Server

Standard OAuth authentication flows expect a desktop environment with a web browser to handle login redirects. On a pure headless SSH connection, these flows will freeze or fail. You can handle headless authentication using the methods below.

### Method A: The OAuth Device Flow (For CLI Tools)
Modern CLIs (like the GitHub CLI `gh` or `gemini`) support "Device Code" OAuth specifically for headless hardware. 

1. **Force Headless Mode:** Before running your CLI, set the `NO_BROWSER` environment variable so the app doesn't attempt to open a hidden web browser.
   ```bash
   export NO_BROWSER=true
   ```
   *(Tip: Add `export NO_BROWSER=true` to your `~/.bashrc` to make this permanent.)*
2. Initiate the login command:
   ```bash
   gemini auth
   # or
   gh auth login
   ```
3. The CLI will detect it is in headless mode and output a URL (e.g., `https://google.com/device`) along with an 8-digit **Device Code**.
4. On your local laptop or phone, open that URL, log into your account, and enter the 8-digit code. The headless server will automatically detect the approval and complete the login process.

### Method B: Classic SSH Keys (For Git Authentication)
For automated services (or simple `git push`/`git pull` traffic) where the Device Flow isn't supported, generate a modern SSH key:

1. Generate an Ed25519 key directly on the headless machine:
   ```bash
   ssh-keygen -t ed25519 -C "headless-node@local"
   ```
2. Start the SSH agent and add your key:
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_ed25519
   ```
3. View the public key:
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
4. Manually copy the output text. Open your web browser on your local laptop, go to your GitHub/GitLab "SSH Keys" settings panel, and paste the key.

---

## 4. Installing CasaOS (Touch-Friendly Dashboard)

CasaOS provides a visually appealing, "home-screen" style dashboard for your headless server. It is ideal for iPad users as it uses large touch-friendly icons for app management and file browsing.

### Standard Installation
If your system has plenty of free space on the root partition, run:
```bash
curl -fsSL https://get.casaos.io | sudo bash
```

### Troubleshooting: "No Space Left" or "Permission Denied"
If you are running from a small partition (like a 20GB USB boot) or a partition with `noexec` restrictions (like some external mounts), follow these rescue steps:

1. **Free Up Space:** Clear system logs and the package cache.
   ```bash
   sudo apt clean
   sudo journalctl --vacuum-time=1d
   ```

2. **Redirect Temporary Files:** Use a larger partition (e.g., your mounted home drive) for the installer's extractions.
   ```bash
   mkdir -p /path/to/large/drive/tmp_installer
   export TMPDIR=/path/to/large/drive/tmp_installer
   ```

3. **Bypass Noexec Restrictions:** Copy the installer to `/var/tmp` and run it from there to ensure it has script execution permissions.
   ```bash
   curl -fsSL https://get.casaos.io -o casaos_install.sh
   cp casaos_install.sh /var/tmp/casaos_install.sh
   cd /var/tmp
   sudo -E bash ./casaos_install.sh
   ```
   *(The `-E` flag ensures your `TMPDIR` variable is passed to the root installer.)*

