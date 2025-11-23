# Ubuntu Based Kiosk (UBK)

**Current Version:** 0.9.7 (check script header for latest version)  
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
wget https://github.com/outis1one/ubk/raw/main/install_kiosk_0.9.7.sh
chmod +x install_kiosk_0.9.7.sh
./install_kiosk_0.9.7.sh
```

The installer will guide you through configuration during setup.

---

## Core Features

### Multi-Site Management
- **Single or multiple sites** with independent configurations
- **Auto-rotation** - Sites rotate automatically based on duration
- **Manual sites** - Duration = 0, accessible via swipe only
- **Hidden sites** - Duration = -1, PIN-protected access
- **Home URL** - Auto-return after inactivity on other sites
- **Pause functionality** - Temporarily pause rotation (configurable per-site)

### Touch Controls
- **2-finger horizontal swipe** - Switch between sites
- **3-finger up swipe** - Access hidden tabs (PIN required)
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
- **SHA-256 hashed passwords**
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
- **Emergency WiFi Hotspot** - Auto-starts if no internet after boot
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
- **VT switching disabled** (Ctrl+Alt+F1-F12 blocked)
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

### Menu System Access

```bash
# Run installer script again to access menu
./install_kiosk_0.9.7.sh

# Menu structure:
# 1. Core Settings - Sites, WiFi, schedules, passwords
# 2. Addons - LMS, CUPS, VNC, VPNs
# 3. Advanced - Diagnostics, logs, Electron updates
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

**Hidden (duration = -1):**
- Accessible via 3-finger up swipe + PIN
- PIN stored in `/home/kiosk/kiosk-app/.jitsi-pin`
- Default PIN: 1234
- Hidden from normal rotation

### Inactivity Extensions

When "Are you still here?" prompt appears:
- **"Yes, I'm still here"** - Reset all timers, stay on current page
- **Time extensions** (15m, 30m, 1h, 2h) - Pause rotation and inactivity
- **"No, go home"** - Return to home URL immediately
- Extensions pause BOTH rotation and lockout timers
- Maximum extension: 4 hours (safety timeout)

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

### Mumble Client (Voice Communication)
- **License:** BSD-3-Clause
- **Source:** https://www.mumble.info
- **Repository:** https://github.com/mumble-voip/mumble
- **Full License:** https://github.com/mumble-voip/mumble/blob/master/LICENSE
- **Note:** Used in separate voice communication components

### Murmur Server (Mumble Server)
- **License:** BSD-3-Clause
- **Source:** https://www.mumble.info
- **Repository:** https://github.com/mumble-voip/mumble
- **Full License:** https://github.com/mumble-voip/mumble/blob/master/LICENSE
- **Note:** Used in separate voice communication components

### TalkKonnect (Mumble PTT Client)
- **License:** Mozilla Public License 2.0 (MPL-2.0)
- **Source:** https://github.com/talkkonnect/talkkonnect
- **Repository:** https://github.com/talkkonnect/talkkonnect
- **Full License:** https://github.com/talkkonnect/talkkonnect/blob/master/LICENSE
- **Note:** Used in separate voice communication components

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

**Current Version:** 0.9.7 - Site-Specific Extension Fix

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

*Last Updated: November 2025*  
*Version: Check script header for current version*
