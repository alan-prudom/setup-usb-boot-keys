# VNC xstartup Update

**Date**: 2026-04-03
**Action**: Updated `~/.vnc/xstartup` 

## Details
Replaced the default VNC `xstartup` configuration on the server to match the recommended configuration outlined in `headless_setup_guide.md`. 

### Changes Made:
- Removed `exec /usr/bin/mate-session &` which was previously setting up the MATE desktop environment.
- Switched to XFCE desktop environment by adding `exec dbus-launch xfce4-session`.
- Implemented Wayland crash prevention by unsetting `WAYLAND_DISPLAY` explicitly (`unset WAYLAND_DISPLAY` and `export WAYLAND_DISPLAY=`).
- Cleaned up outdated VNC desktop entries and retained `unset SESSION_MANAGER` and `unset DBUS_SESSION_BUS_ADDRESS`.

### Rationale
By default, modern environments try to initialize a Wayland display inside VNC, immediately resulting in a "Connection Refused" error due to session crashes. Forcing standard X11 via `dbus-launch` and aggressively unsetting Wayland ensures that TigerVNC serves XFCE components properly.
