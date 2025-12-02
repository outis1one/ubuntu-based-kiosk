# Ubuntu Based Kiosk (UBK)

**Current Version:** 0.9.7-4 (check script header for latest version)
**Built with Claude Sonnet 4/.5 AI assistance**
**License:** GPL v3 - Keep derivatives open source
**Repository:** https://github.com/outis1one/ubk/

---

## Target Systems

- Ubuntu 24.04+ Server (minimal install recommended)
- Raspberry Pi 4+ (with or without touchscreen) - *untested*
- Laptops, desktops, all-in-ones, 2-in-1s
- Touch support optional (works with keyboard/mouse)

---

## ⚠️ Security Notice

**This is NOT suitable for secure locations or public kiosks.**

- Do NOT use as a replacement for hardened kiosk solutions
- Designed for home/office/trusted environments only
- Use entirely at your own risk
- No warranty or security guarantees provided

---

## Purpose

Home/office kiosk for reusing old hardware, displaying:

- Self-hosted services (Immich, MagicMirror2, Home Assistant, Plex, Jellyfin, Emby)
- Web dashboards and digital signage
- Photo slideshows and family calendars
- Video conferencing (Jitsi, Zoom, Google Meet)
- Any web-based content

---

## Quick Install

```bash
# Install Ubuntu 24.04 Server
# Configure WiFi if no ethernet available
# Enable SSH during installation

# Download and run installer
wget https://github.com/outis1one/ubk/raw/main/install_kiosk_0.9.7-4.sh
chmod +x install_kiosk_0.9.7-4.sh
./install_kiosk_0.9.7-4.sh
```

The installer will guide you through configuration during setup.

---

## Core Features

### Multi-Site Management
- **Single or multiple sites** with independent configurations
- **Auto-rotation** - Sites rotate automatically based on duration
- **Manual sites** - Duration = 0, accessible via swipe only, trigger inactivity timeout
- **Hidden sites** - Duration = -1, PIN-protected access, trigger inactivity timeout
- **Home URL** - Auto-return after inactivity on manual or hidden sites
- **Pause functionality** - Temporarily pause rotation (configurable per-site)

### Touch Controls
- **2-finger horizontal swipe** - Switch between sites
- **3-finger up swipe** - Access hidden tabs (PIN required)
- **3-finger down swipe** - Return to normal tabs (from hidden tabs)
- **1-finger swipe** (dual mode) - Navigate within page (arrow keys)
- **On-screen keyboard** - Auto-shows on text fields or click keyboard icon

### On-Screen Keyboard
- **HTML-based keyboard** with full QWERTY layout
- **Auto-show on text fields** (optional)
- **30-second auto-close** after inactivity
- **Shift/Caps Lock support**
- **Special characters** via shift keys
- Works alongside physical keyboard

### Password Protection & Lockout
- **Session lockout** after configured inactivity
- **Scheduled lockout** at specific time daily
- **Display wake lockout** - Require password after display schedule
- **Boot password** option - Require password on system startup
- **Full screen blocking** during lockout (no content visible)

### Navigation Security
- **Restricted** - Exact URL only, no link clicking
- **Same-origin** - Links within same domain only (recommended)
- **Open** - Unrestricted browsing (trusted environments only)

### Scheduling System
- **Power schedule** - Auto-shutdown and RTC wake (hardware dependent)
- **Display schedule** - Turn display off/on at specific times
- **Quiet hours** - Mute audio or stop Squeezelite during hours
- **Electron reload** - Periodic restart to prevent memory leaks

### Media Playback Intelligence
- **Auto-detects playing media** (HTML5 video/audio, YouTube, Plex, Jellyfin, Emby)
- **Pauses rotation** during media playback
- **Grace period** after media stops
- **Respects user activity** while watching

---

## Optional Add-ons

### Audio
- **Lyrion Music Server (LMS)** - Formerly Logitech Media Server
- **Squeezelite Player** - Network audio player for LMS
- **PipeWire audio** - Modern Linux audio stack
- **Volume controls** - Hardware button support

### Printing
- **CUPS printing system**
- **Network printer sharing**
- **IPP Everywhere support**
- **PDF printing** via cups-pdf

### Remote Access
- **VNC** - x11vnc for remote desktop
- **WireGuard VPN** - Config paste support
- **Tailscale VPN** - Auth key support
- **Netbird VPN** - Setup key support

### Advanced
- **Emergency WiFi Hotspot** - Auto-starts if no internet after boot (configurable during install)
- **Virtual Console Access** - Ctrl+Alt+F1-F8 terminal login (configurable during install)
- **Complete Uninstall** - Full system cleanup and kiosk removal
- **SSH remote access** - For configuration and troubleshooting

---

## What This Script Installs

### Core Components
- **Electron** v33.4.11 (Chromium-based app framework)
- **Node.js** v20.x with npm
- **Openbox** - Lightweight window manager
- **LightDM** - Display manager with autologin
- **xorg** - X11 server and utilities
- **unclutter** - Hide mouse cursor
- **Hardware acceleration** - VAAPI, Mesa drivers

### Audio Stack
- **PipeWire** - Modern audio/video server
- **PipeWire-Pulse** - PulseAudio compatibility
- **WirePlumber** - Session manager
- **ALSA** utilities

### System Services
- **systemd-timesyncd** - NTP time sync
- **acpid** - Power button handling
- **ufw** - Uncomplicated Firewall
- **Network Manager** or netplan for networking

### Development Tools
- **build-essential** - GCC, make, etc.
- **Python 3** with evdev for PTT
- **jq** - JSON processing

---

## System Behavior

### Security & Lockdown
- **Autologin** as kiosk user
- **Virtual consoles** (Ctrl+Alt+F1-F8) - Optional, configurable during install
- **X server key combinations disabled** (Ctrl+Alt+Backspace)
- **Right-click disabled** in kiosk app
- **Screen blanking disabled** with schedule awareness
- **DPMS management** - Aggressive keep-alive with schedule respect

### Audio Management
- **PipeWire watchdog** - Auto-restart if audio fails
- **Volume persistence** - Speakers 100%, Mic 100% and unmuted
- **Quiet hours aware** - Respects audio schedules
- **User services** - Audio runs under kiosk user

### Network
- **WiFi configuration** - WPA2, netplan-based
- **Multi-method WiFi scan** - nmcli, iw, wpa_cli fallbacks
- **Watchdog support** - Auto-revert bad WiFi configs
- **Emergency hotspot** - Fallback if no internet

---

## Maintenance & Troubleshooting

### Service Management

```bash
# Restart kiosk display
sudo systemctl restart lightdm

# View Electron logs
sudo tail -f /home/kiosk/electron.log

# Check service status
systemctl status lightdm
systemctl status squeezelite
sudo systemctl --user -M kiosk@ status pipewire
```

### Common Issues

**No display after boot:**
```bash
# Check LightDM status
sudo journalctl -u lightdm -n 50

# Verify kiosk user
id kiosk

# Check X11 authorization
sudo -u kiosk DISPLAY=:0 xdpyinfo
```

**Audio not working:**
```bash
# Check PipeWire (use menu: Advanced → Audio Diagnostics)
sudo -u kiosk pactl info

# Restart audio
sudo systemctl restart lightdm
```

**Touch not working:**
```bash
# List input devices
xinput list

# Check Electron logs for touch events
sudo tail -f /home/kiosk/electron.log | grep TOUCH

# Test gestures (should show in logs):
# - 3-finger UP = "[TOUCH] 3-finger UP - show hidden tab"
# - 3-finger DOWN = "[TOUCH] 3-finger DOWN - return to normal tabs"
# - 2-finger HORIZONTAL = "[MANUAL] User switched tab..."
```

**Hidden sites not showing:**
```bash
# Check PIN file exists
ls -la /home/kiosk/kiosk-app/.jitsi-pin

# View current PIN
sudo cat /home/kiosk/kiosk-app/.jitsi-pin

# Check for hidden sites in config
sudo jq '.tabs[] | select(.duration == -1)' /home/kiosk/kiosk-app/config.json

# Check if inactivity timeout is working on hidden tabs
sudo tail -f /home/kiosk/electron.log | grep HOME
# Should show: "[HOME] HIDDEN IDLE: Xm Ys / Ym Ys"
```

**Inactivity prompt not appearing:**
```bash
# Check home tab configuration
sudo jq '.homeTabIndex, .inactivityTimeout' /home/kiosk/kiosk-app/config.json

# Watch for inactivity logging
sudo tail -f /home/kiosk/electron.log | grep HOME

# Manual site: "[HOME] 🏠 MANUAL IDLE: 1m 45s / 2m 0s"
# Hidden site: "[HOME] 🏠 HIDDEN IDLE: 1m 45s / 2m 0s"
# Prompt shown: "[HOME] 🔔 *** SHOWING PROMPT NOW (hidden tab) ***"
```

**Keyboard not appearing:**
```bash
# Check keyboard button setting
sudo grep enableKeyboardButton /home/kiosk/kiosk-app/config.json

# View keyboard events
sudo tail -f /home/kiosk/electron.log | grep KEYBOARD
```

### Adding Printers to CUPS

**1. Access CUPS Web Interface:**
```
http://<kiosk-ip-address>:631/admin
```
Login with the username and password you used during Ubuntu installation.

**2. Click "Add Printer"**

**3. Find Your Printer URI**

CUPS needs a device URI to connect to your printer. Here's how to find it:

**For Network Printers (Most Common):**

From Windows, find the printer's URI:
1. Right-click printer → **Printer Properties** → **Ports** tab
2. Look for the checked port, note the format:

**HP Network Printers:**
- Windows shows: `IP_192.168.1.100` or similar
- CUPS URI: `hp:/net/<printer-model>?ip=192.168.1.100`
- Alternative: `socket://192.168.1.100:9100`

**Generic Network Printers (IPP):**
- Windows shows: `http://192.168.1.100/ipp/print` or similar
- CUPS URI: `ipp://192.168.1.100/ipp/print`
- Alternative: `http://192.168.1.100:631/ipp/print`
gumble
**Generic Network Printers (Socket/JetDirect):**
- Windows shows: `Standard TCP/IP Port` on `192.168.1.100`
- CUPS URI: `socket://192.168.1.100:9100`
- Port 9100 is standard for HP JetDirect protocol

**USB Printers:**
- CUPS auto-detects these
- URI looks like: `usb://HP/LaserJet%20P1102`
- Select from "Local Printers" list in CUPS

**4. Select Driver**

After entering URI, CUPS will ask for a driver:
- Search for your printer model
- If not found, try "Generic PCL" or "Generic PostScript"
- For HP printers, install `hplip`: `sudo apt install hplip`

**5. Set as Default (Optional)**

Administration → Set Default Printer

**6. Print Test Page**

Printers → Your Printer → Maintenance → Print Test Page

**Quick Reference - Common URIs:**
```bash
# HP Network Printer
hp:/net/HP_LaserJet_P3015?ip=192.168.1.100

# Generic Network (Socket/JetDirect - Port 9100)
socket://192.168.1.100:9100

# Generic Network (IPP)
ipp://192.168.1.100/ipp/print

# Shared Windows Printer
smb://WORKGROUP/COMPUTER/PrinterName
```

**Troubleshooting:**
- **Printer not responding:** Check firewall, ensure kiosk can ping printer IP
- **Wrong driver:** Try Generic PostScript or PCL drivers
- **Authentication failed:** Verify Windows printer sharing is enabled
- **Can't find printer:** Use `lpinfo -v` to list all available devices

---

## Touch Gesture Quick Reference

| Gesture | Fingers | Direction | Action |
|---------|---------|-----------|--------|
| Swipe | 2 | Left/Right | Switch between sites |
| Swipe | 1 | Left/Right | Navigate within page (arrow keys) |
| Swipe | 3 | Down | Toggle hidden tabs (PIN required) |

**Keyboard Shortcuts:**
- `Ctrl+Tab` or `Ctrl+]` - Next tab
- `Ctrl+Shift+Tab` or `Ctrl+[` - Previous tab
- `Alt+Right/Left` - Next/Previous tab
- `F10` or `Ctrl+H` - Toggle hidden tabs
- `Escape` - Return to normal tabs (from hidden)
- `Ctrl+Alt+Delete` or `Ctrl+Alt+P` - Power menu
- `Ctrl+K` - Toggle keyboard

---

### Menu System Access

```bash
# Run installer script again to access menu
./install_kiosk_0.9.7-4.sh

# Menu structure:
# 1. Core Settings - Sites, WiFi, schedules, passwords, full reinstall, complete uninstall
# 2. Addons - LMS, CUPS, VNC, VPNs
# 3. Advanced - Diagnostics, logs, Electron updates, virtual consoles, emergency hotspot
# 4. Restart Kiosk Display
```

### Updating Electron

```bash
# Via menu: Advanced → Manual Electron Update
# Or manually:
cd /home/kiosk/kiosk-app
sudo -u kiosk npm install electron@latest
sudo systemctl restart lightdm
```

---

## Configuration Files

### Main Config
`/home/kiosk/kiosk-app/config.json`
```json
{
  "autoswitch": true,
  "swipeMode": "dual",
  "allowNavigation": "same-origin",
  "homeTabIndex": 0,
  "inactivityTimeout": 120,
  "enablePauseButton": true,
  "enableKeyboardButton": true,
  "enablePasswordProtection": false,
  "tabs": [
    {
      "url": "https://example.com",
      "duration": 180,
      "username": "",
      "password": ""
    }
  ]
}
```

### Key Config Values
- **duration**: `>0` = auto-rotate (seconds), `0` = manual only, `-1` = hidden
- **swipeMode**: `"dual"` = 2-finger nav + 1-finger arrows, `"standard"` = 2-finger only
- **allowNavigation**: `"restricted"` | `"same-origin"` | `"open"`
- **homeTabIndex**: Tab to return to after inactivity (`-1` = disabled)
- **inactivityTimeout**: Seconds before showing "still here?" prompt
- **lockoutTimeout**: Minutes of inactivity before lockout (0 = disabled)
- **lockoutAtTime**: Daily lockout time in `"HH:MM"` format
- **requirePasswordOnBoot**: `true` = password required on system startup

**Note:** Config files may contain `lockoutActiveStart` and `lockoutActiveEnd` fields from earlier versions. These are not currently functional and are ignored by the application.

### Hidden Sites PIN
`/home/kiosk/kiosk-app/.jitsi-pin`

The PIN file controls access to hidden sites (duration = -1):
- **Default:** `1234`
- **Configure via:** Main Menu → Core Settings → Sites → Configure Hidden Sites PIN
- **Disable PIN:** Set content to `NOPIN` to allow any entry
- **Custom PIN:** 4-8 digits

```bash
# Set custom PIN
echo "5678" | sudo -u kiosk tee /home/kiosk/kiosk-app/.jitsi-pin

# Disable PIN protection
echo "NOPIN" | sudo -u kiosk tee /home/kiosk/kiosk-app/.jitsi-pin
```

---

## Advanced Features

### Site Duration Modes

**Auto-Rotate (duration > 0):**
- Site displays for specified seconds
- Auto-advances to next rotation site
- Pause button available
- Respects media playback

**Manual Only (duration = 0):**
- Site accessible via swipe
- Never auto-rotates
- No pause button (not needed)
- Can be set as Home URL
- Triggers inactivity timeout (returns to home after idle time)

**Hidden (duration = -1):**
- Toggle visibility via 3-finger down swipe + PIN, or F10 key
- Also use Escape key to return to normal tabs
- PIN stored in `/home/kiosk/kiosk-app/.jitsi-pin`
- Default PIN: 1234 (configurable via Sites menu)
- PIN can be 4-8 digits or disabled completely
- Hidden from normal rotation
- **Triggers inactivity timeout** (returns to home after idle time, just like manual sites)

#### Why Use Hidden Tabs?

Hidden tabs are perfect for scenarios where you need access to sensitive or private content on a shared/public kiosk:

**Private Communication:**
- Video conferencing (Jitsi Meet, Zoom, Google Meet)
- Private messaging or chat applications
- Internal communication tools for staff only
- Conference room scheduling interfaces

**Administrative Access:**
- Server administration panels (Proxmox, TrueNAS, router interfaces)
- Security camera feeds
- Home automation controls (Home Assistant, OpenHAB)
- Network monitoring dashboards

**Content Management:**
- Digital signage content editors
- Photo album management (Immich, PhotoPrism)
- Media server administration (Plex, Jellyfin)
- Calendar and scheduling updates

**Secure Entertainment:**
- Personal streaming accounts (prevent others from accessing your watch history)
- Gaming platforms or cloud gaming services
- Adult content controls (parental access only)
- Personal social media (Facebook, Instagram, etc.)

**Business Use Cases:**
- Employee time tracking systems
- Inventory management interfaces
- Point-of-sale backend access
- Staff scheduling and shift management

**Example Scenarios:**

1. **Reception Kiosk:** Public-facing sites rotate (directory, weather, news), but staff can swipe up with PIN to access appointment scheduling, visitor management, or internal messaging.

2. **Family Room Display:** Displays photo slideshows, calendar, and weather, but parents can PIN-access streaming services, smart home controls, or security cameras.

3. **Digital Signage:** Publicly shows announcements and menus, but managers can PIN-access the content management system to make updates.

4. **Conference Room Display:** Shows meeting schedules and company news, but attendees can PIN-access video conferencing or presentation tools.

The hidden tab system provides a balance between public accessibility and private functionality without needing to physically access a terminal or reconfigure the system.

### Inactivity Extensions

When "Are you still here?" prompt appears (on manual or hidden sites):
- **"Yes, I'm still here"** - Reset all timers, stay on current page
- **Time extensions** (15m, 30m, 1h, 2h) - Pause rotation and inactivity
- **"No, go home"** - Return to home URL immediately
- Extensions pause BOTH rotation and lockout timers
- Maximum extension: 4 hours (safety timeout)

**Triggers on:**
- Manual sites (duration = 0) after inactivity timeout
- Hidden sites (duration = -1) after inactivity timeout  
- Does NOT trigger on auto-rotating sites (duration > 0) - they use pause button instead

### Lockout Behavior

**Triggers:**
- Inactivity timeout expires (if configured)
- Scheduled lockout time reached (if configured)
- Display schedule wake-up (if password-on-wake enabled)
- System boot (if requirePasswordOnBoot enabled)

**During Lockout:**
- Full black screen (no content visible)
- All browser views detached for security
- Password prompt displayed
- Limited power menu (no Reload option to prevent bypass)
- Rotation and timers paused

**After Unlock:**
- Returns to previous site
- Timers reset
- Normal operation resumes

### Media Detection

Detects and pauses for:
- HTML5 `<video>` and `<audio>` elements
- YouTube embeds and direct links
- Plex Web player
- Jellyfin Web player
- Emby Web player
- Vimeo, Dailymotion, Twitch embeds

### Display Schedule with Password

Example: Display off 22:00-06:00, optional password on wake
```bash
# Configure via menu: Core Settings → Power/Display/Quiet Hours
# Then: Core Settings → Password Protection

# Behavior:
# - Display turns off at 22:00 (hardware DPMS)
# - Display turns on at 06:00
# - If password protection enabled and configured for display wake:
#   - Password required to unlock
#   - Creates /home/kiosk/kiosk-app/.display-wake flag
#   - main.js detects flag and shows lockout screen
# - Otherwise, display just turns on normally
```

---

## Installation & Management Features

### Virtual Console Configuration

Virtual consoles provide terminal access via Ctrl+Alt+F1 through F8 keyboard combinations.

**During Installation:**
- Prompted at the end of initial setup
- Default: ENABLED (Ubuntu standard behavior)
- Option to disable for enhanced security

**Security Considerations:**

*Enabled (Default):*
- Allows manual terminal login for troubleshooting
- Useful for SSH failures or network issues
- Standard Ubuntu/Linux behavior
- Can login with kiosk user credentials or main user account

*Disabled (More Secure):*
- Blocks direct terminal access
- Forces all access through SSH or menu system
- Better for public kiosks or untrusted environments
- Can still be re-enabled via Advanced menu (requires existing SSH access)

**Post-Install Management:**
```bash
# Access via menu: Advanced → Virtual Consoles (option 7)
# Note: Changes require restarting the display manager to take effect

# Manual enable
for i in {1..8}; do sudo systemctl unmask getty@tty$i.service; done
sudo systemctl daemon-reload
sudo systemctl restart lightdm

# Manual disable
for i in {1..8}; do sudo systemctl mask getty@tty$i.service; done
sudo systemctl daemon-reload
sudo systemctl restart lightdm
```

**Important Notes:**
- **Version 0.9.7-4** fixed Ctrl+Alt+F1-F8 key combinations (now properly enables/disables X11 VT switching)
- If you enabled virtual consoles in an earlier version, you must re-enable them from the menu for keys to work
- Changes require restarting lightdm: `sudo systemctl restart lightdm`

**Typical TTY Layout:**
- TTY1-6: Login consoles (if enabled)
- TTY7: Graphical kiosk display (X11/LightDM)
- TTY8: Available for additional services

### Emergency WiFi Hotspot

Automatically creates a WiFi access point when internet connectivity is lost.

**During Installation:**
- Prompted at the end of initial setup
- Optional configuration with custom SSID and password
- Can be deferred and configured later

**How It Works:**
1. Service monitors internet connectivity every 30 seconds
2. When internet is lost, automatically:
   - Creates WiFi hotspot with configured credentials
   - Assigns IP address (default: 10.42.0.1)
   - Displays on-screen notification with connection details
   - Serves simple web page at http://10.42.0.1
3. When internet returns, hotspot automatically shuts down

**Use Cases:**
- Initial WiFi configuration without keyboard
- Network troubleshooting when SSH is unavailable
- Remote location setup without IT staff present
- Automatic failover for temporary connectivity issues

**Configuration:**
```bash
# Access via menu: Advanced → Emergency Hotspot (option 9)

# Default credentials:
SSID: Kiosk-Emergency
Password: kioskhotspot123

# Once connected to hotspot:
# - SSH: ssh user@10.42.0.1
# - Web: http://10.42.0.1 (shows connection info)
# - Run installer script to reconfigure WiFi
```

**Files Created:**
- `/usr/local/bin/kiosk-emergency-hotspot` - Main service script
- `/etc/systemd/system/kiosk-emergency-hotspot.service` - Systemd service

### Complete Uninstall

Full system cleanup that removes all kiosk components and restores the system to pre-installation state.

**Access:**
```bash
# Core Settings menu → option 11
./install_kiosk_0.9.7-4.sh
# Choose: Core Settings → Complete Uninstall
```

**What Gets Removed:**
- Kiosk user and all user data
- All Electron and Node.js installations
- LightDM and Openbox window manager
- All systemd services and timers
- All kiosk scripts and configurations
- CUPS printing system
- VNC server
- Emergency hotspot configuration
- All scheduled tasks (power, display, quiet hours)

**What Gets Preserved:**
- VPN configurations (if not manually removed)
- System packages (Ubuntu base system)
- Network configuration (WiFi, ethernet)
- SSH server and settings
- User accounts (except kiosk user)

**Safety Features:**
- Requires typing "UNINSTALL" to confirm
- Re-enables virtual consoles automatically
- Stops all services before removal
- Offers optional reboot after completion
- No way to undo - creates clean slate

**Use When:**
- Repurposing hardware for different use
- Testing/development cleanup
- Complete fresh start needed
- Removing kiosk from production system

---

## Third-Party Software Licenses

This project bundles or installs several open-source components under their respective licenses:

### Electron
- **License:** MIT
- **Source:** https://www.electronjs.org
- **Full License:** https://github.com/electron/electron/blob/main/LICENSE

### Chromium (bundled with Electron)
- **License:** BSD-3-Clause
- **Source:** https://www.chromium.org
- **Full License:** https://chromium.googlesource.com/chromium/src/+/main/LICENSE

### Node.js
- **License:** MIT
- **Source:** https://nodejs.org
- **Full License:** https://github.com/nodejs/node/blob/main/LICENSE

### npm Packages
- **Licenses:** Vary by package (MIT, Apache-2.0, BSD, etc.)
- **Source:** https://www.npmjs.com
- **Note:** Check each package's LICENSE file individually

### CUPS (Common Unix Printing System)
- **License:** Apache License 2.0
- **Source:** https://www.cups.org
- **Full License:** https://github.com/OpenPrinting/cups/blob/master/LICENSE

### Squeezelite
- **License:** GPL-3.0
- **Source:** https://github.com/ralph-irving/squeezelite
- **Full License:** https://github.com/ralph-irving/squeezelite/blob/master/LICENSE.txt
- **Note:** README previously incorrectly stated GPL-2.0

### Lyrion Music Server (formerly Logitech Media Server)
- **License:** GPL-2.0-or-later
- **Source:** https://lyrion.org
- **Repository:** https://github.com/LMS-Community/slimserver

### PipeWire
- **License:** MIT
- **Source:** https://pipewire.org
- **Full License:** https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/master/LICENSE

### FFmpeg (if installed)
- **License:** LGPL-2.1-or-later (default build) or GPL-2.0-or-later (with GPL components)
- **Source:** https://ffmpeg.org
- **License Info:** https://ffmpeg.org/legal.html

### Unclutter-xfixes
- **License:** MIT
- **Source:** https://github.com/Airblader/unclutter-xfixes
- **Full License:** https://github.com/Airblader/unclutter-xfixes/blob/master/LICENSE

### Openbox
- **License:** GPL-2.0-or-later
- **Source:** http://openbox.org
- **Repository:** https://github.com/danakj/openbox

### LightDM
- **License:** GPL-3.0-or-later
- **Source:** https://github.com/canonical/lightdm
- **Full License:** https://github.com/canonical/lightdm/blob/main/COPYING

### x11vnc
- **License:** GPL-2.0-or-later
- **Source:** https://github.com/LibVNC/x11vnc
- **Full License:** https://github.com/LibVNC/x11vnc/blob/master/COPYING

### WireGuard Tools
- **License:** GPL-2.0
- **Source:** https://www.wireguard.com
- **Repository:** https://git.zx2c4.com/wireguard-tools

### Tailscale
- **License:** BSD-3-Clause
- **Source:** https://tailscale.com
- **Repository:** https://github.com/tailscale/tailscale
- **Full License:** https://github.com/tailscale/tailscale/blob/main/LICENSE

### Netbird
- **License:** BSD-3-Clause
- **Source:** https://netbird.io
- **Repository:** https://github.com/netbirdio/netbird
- **Full License:** https://github.com/netbirdio/netbird/blob/main/LICENSE

### Murmur Server (Mumble Server)
- **License:** BSD-3-Clause
- **Source:** https://www.mumble.info
- **Repository:** https://github.com/mumble-voip/mumble
- **Full License:** https://github.com/mumble-voip/mumble/blob/master/LICENSE
- **Note:** Used in separate voice communication components

### Gumble (Mumble Cli Client) (Mumble Client Library for Go)
- * **License:** Mozilla Public License 2.0 (MPL-2.0)
- * **Source:** https://github.com/layeh/gumble
- * **Full License:** https://github.com/layeh/gumble/blob/master/LICENSE
- * **Note:** Used as the core client library for Mumble protocol integration


---

## UBK Project License

The UBK installer script and original code components are licensed under **GPL-3.0-or-later**.

See the LICENSE file in the repository for full terms.

**Keep derivatives open source** - Any modifications or derivative works must also be released under GPL-3.0-or-later.

---

## Disclaimer

- No warranty of any kind is provided
- Use at your own risk
- Not suitable for security-critical deployments
- Aggregates open-source software governed by their respective licenses
- The authors make no warranty regarding modifications by downstream integrators

---

## Project Status & Future Plans

**Current Version:** 0.9.7-4 - Gesture & Console Improvements

**Planned Features:**
- Web-based GUI configuration interface
- All-in-one ISO installer
- Voice communication integration (Mumble/TalkKonnect)
- Enhanced Raspberry Pi support and testing

**Known Limitations:**
- Raspberry Pi support untested in production
- No web-based configuration (CLI menu only)
- Single display only (extended desktop not supported)

---

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Follow existing code style
4. Keep GPL-3.0 compatibility
5. Submit pull request with clear description

---

## Support & Community

- **Repository:** https://github.com/outis1one/ubk/
- **Issues:** https://github.com/outis1one/ubk/issues
- **Discussions:** https://github.com/outis1one/ubk/discussions

---

## Credits

Built with assistance from **Claude Sonnet 4/.5** (Anthropic AI)

Special thanks to the maintainers of all upstream projects that make UBK possible.

---

*Last Updated: December 2, 2024*
*Version: 0.9.7-4*
