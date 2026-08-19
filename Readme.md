# Ubuntu Based Kiosk

**Current Version:** 2.13.0 (check script header for latest version)
**Built with Claude Sonnet 4.6 AI assistance**
**License:** GPL v3 - Keep derivatives open source
**Repository:** https://github.com/outis1one/ubuntu-based-kiosk/

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
# ***Do not use "kiosk" as a user name when installing, the script creates a restricted user named kiosk and the script will not install if the sudo user/user name when setting up the system is "kiosk".***
# Configure WiFi if no ethernet available
# Enable SSH during installation

# Download and run the installer
wget https://github.com/outis1one/ubuntu-based-kiosk/raw/main/ubuntu-based-kiosk.sh
chmod +x ubuntu-based-kiosk.sh && ./ubuntu-based-kiosk.sh
```

The installer will guide you through configuration during setup.

> The modular `./install.sh` (see "Modular Management" below) can also
> provision a kiosk from scratch now, and has its own Upgrade, as an
> alternative to the single-file installer above. `ubuntu-based-kiosk.sh`
> remains the more battle-tested path and the only one that supports
> Full Reinstall of an existing install.

---

## Offline / Air-Gapped Download

If the kiosk machine can't reach GitHub directly (no browser, restrictive proxy, or you just prefer to grab the script on another computer and carry it over via USB), download it ahead of time instead of using the `curl`/`wget` one-liner above.

> **Note:** This only avoids needing internet access *to fetch the script*. The installer itself still requires the kiosk machine to have internet access while it runs — it uses `apt` to install packages, pulls Node.js from NodeSource, and runs `npm install` to fetch Electron (~120MB). There is currently no fully air-gapped/offline package bundle.

**On a machine with internet access:**

```bash
# Option A: download just the installer script
wget https://github.com/outis1one/ubuntu-based-kiosk/raw/main/ubuntu-based-kiosk.sh

# Option B: download the whole repo as a ZIP (includes install.sh, addon scripts, and older archived installer versions)
wget https://github.com/outis1one/ubuntu-based-kiosk/archive/refs/heads/main.zip
unzip main.zip
```

Copy the downloaded `.sh` file (or the extracted ZIP contents) to a USB drive, then on the kiosk machine:

```bash
# Mount the USB drive and copy the script over, then:
chmod +x ubuntu-based-kiosk.sh
./ubuntu-based-kiosk.sh
```

The kiosk machine still needs a working internet connection (ethernet, or WiFi configured during Ubuntu install) for the script to complete.

---

## Core Features

### Multi-Site Management
- **Single or multiple sites** with independent configurations
- **Named sites** - Optional friendly names for easy identification in navigation menu
- **Auto-rotation** - Sites rotate automatically based on duration
- **Manual sites** - Duration = 0, accessible via swipe only, trigger inactivity timeout
- **Hidden sites** - Duration = -1, PIN-protected access, trigger inactivity timeout
- **Home URL** - Auto-return after inactivity on manual or hidden sites
- **Pause functionality** - Temporarily pause rotation (configurable per-site)
- **Navigation menu** - Quick access to all sites via key icon (top-left hot corner)

### Touch Controls
- **2-finger horizontal swipe** - Switch between sites
- **3-finger down swipe** - Toggle hidden tabs (PIN required to show, swipe again to hide)
- **1-finger swipe** (dual mode) - Navigate within page (arrow keys)
- **On-screen keyboard** - Auto-shows on text fields or click keyboard icon
- **Navigation menu** - Click key icon (top-left) to access site list and gesture cheat sheet

### On-Screen Keyboard
- **HTML-based keyboard** with full QWERTY layout
- **Auto-show on text fields** (optional)
- **30-second auto-close** after inactivity
- **Shift/Caps Lock support**
- **Special characters** via shift keys
- Works alongside physical keyboard

### Password Protection & Lockout (all are optional)
- **Session lockout** after configured inactivity
- **Scheduled lockout** at specific time daily 
- **Display wake lockout** - Require password after display schedule
- **Boot password** option - Require password on system startup
- **Full screen blocking** during lockout (no content visible)

### Navigation Security
- **Restricted** - Exact URL only, no link clicking
- **Same-origin** - Links within same domain only (recommended)
- **Open** - Unrestricted browsing (trusted environments only)

### Scheduling System (all are optional)
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

### Authentication

#### Authelia Auto-Login (SSO)

Automatically authenticates the kiosk against a self-hosted [Authelia](https://www.authelia.com) instance on every startup. The Authelia password is **not stored in plain text** — it is encrypted with AES-256-CBC using a key derived from the machine's unique `/etc/machine-id`, so the encrypted blob is useless on any other machine.

**Access via menu:** `Addons → 5. Authelia Auto-Login`

After running the addon it prints the full server-side setup, but the summary is below.

##### Kiosk side (SSH in and run the installer)

```bash
ssh user@kiosk-machine
./ubuntu-based-kiosk.sh
# Addons → 5. Authelia Auto-Login
# Enter your Authelia URL, username, and password when prompted
```

##### Authelia server side (Dockerized)

**Step 1 — Generate the argon2 password hash** (run on your Docker host):

```bash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 \
  --password 'yourpassword'
```

Copy the `$argon2id$...` output — that is your hash.

**Step 2 — Add a kiosk user** to `~/docker/authelia/config/users.yml`:

```yaml
kiosk:
  displayname: "Kiosk Display"
  password: '$argon2id$v=19$m=65536,t=3,p=4$<paste hash here>'
  email: kiosk@local.com
  groups:
    - kiosk
```

**Step 3 — MERGE into `~/docker/authelia/config/configuration.yml`** (do not replace your existing config):

**access_control** — Find your **existing** `access_control:` block and add the kiosk rule as the **first** rule inside it.

> **Do NOT create a second `access_control:` block.** YAML silently ignores duplicate keys — Authelia will never see the kiosk rule and the kiosk will get a white screen.

Authelia reads rules top-down — first match wins. The kiosk rule **must** sit above any `two_factor` wildcard rule, otherwise the wildcard matches first.

**Why `one_factor`?** The kiosk authenticates via the API (`/api/firstfactor` — password only). TOTP and WebAuthn require an interactive second step that is impossible from a script, so the kiosk group must use `one_factor`.

*Before (your existing config):*
```yaml
access_control:
  default_policy: deny
  rules:
    - domain: '*.yourdomain.com'
      policy: two_factor
```

*After (add kiosk rule above the two_factor rule — same block, not a new one):*
```yaml
access_control:
  default_policy: deny
  rules:
    - domain: '*.yourdomain.com'   # kiosk first — one_factor only
      subject: 'group:kiosk'
      policy: one_factor
    - domain: '*.yourdomain.com'   # existing rule stays below
      policy: two_factor
```

**session** — Keep your existing session block as-is; no changes needed. The kiosk re-authenticates via API on every startup so session expiry barely matters for it.

If you do **not** yet have a session block, add:

```yaml
session:
  expiration: 8h
  inactivity: 1h
  remember_me: 7d
  cookies:
    - domain: yourdomain.com
      authelia_url: https://auth.yourdomain.com
```

**Step 4 — Restart Authelia:**

```bash
docker compose restart authelia
```

##### How it works

On every kiosk startup, Electron calls Authelia's `/api/firstfactor` endpoint with `keepMeLoggedIn: true` **before** any sites load. Authelia responds with a `Set-Cookie` header that Electron absorbs into its default session. All BrowserViews then load with that session cookie already present.

Because Electron's session persists to disk across reboots (`/home/kiosk/.config/kiosk-app/`), the cookie also survives restarts — the API call on startup just refreshes or extends it.

##### Authelia vs HTTP Basic Auth

Both can be used at the same time — they serve different purposes:

| Method | Where configured | When to use |
|--------|-----------------|-------------|
| **Authelia SSO** | `Addons → Authelia Auto-Login` (global) | Sites protected by an Authelia reverse proxy |
| **HTTP Basic Auth** | Per-site username/password in tab config | Sites that show a browser popup asking for credentials |

---

### Communication
- **Asterisk Intercom** (`./install.sh` → Addons) - connects this kiosk
  as a Baresip SIP extension to an Asterisk server you already have
  running elsewhere; does not install or manage Asterisk itself
  - Manual or auto-answer (intercom) mode
  - Optional TLS/SRTP transport
  - Uninstall support (with or without removing saved credentials)
- **Legacy Easy Asterisk Intercom** (`./ubuntu-based-kiosk.sh` → Addons,
  not yet retired) - the original three-option version: Client Only
  (same Baresip client as above), Server Only, or Full, where Server/
  Full download and run a third-party installer from a separate
  "Easy Asterisk" repository to stand up a whole Asterisk PBX on this
  device. That repository has since gone through a major rework
  upstream, so the modular `./install.sh` version above only carries
  the client/endpoint piece forward - see "Modular Management" below.

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
- **Virtual Console Access** - Ctrl+Alt+F1-F8 terminal login (can enable/disable during install)
- **Complete Uninstall** - Full system cleanup and kiosk removal
- **SSH remote access** - For configuration and troubleshooting

---

## What This Script Installs

### Core Components
- **Electron** v42.x (Chromium-based app framework)
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
- **curl / git** - Downloading and version control
- **net-tools** - Legacy networking utilities (ifconfig, netstat, etc.)
- **ncdu** - Disk usage analyzer for troubleshooting

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

**External monitor/TV (HDMI) shows nothing, or shows a cropped/scaled picture:**

Any connected display beyond the primary is mirrored automatically at the **primary's exact resolution** (not the external display's own native resolution) — both at kiosk login/boot (via Openbox autostart) and live when plugged/unplugged afterward (via a udev rule that triggers `kiosk-hotplug.service`). Both paths call the same `/usr/local/bin/kiosk-mirror-display.sh`. If the external display doesn't natively list the primary's resolution (e.g. a 1366x768 laptop panel mirrored to a 1920x1080-native TV), a matching mode is generated on the fly with `cvt` and forced onto the output — most monitors/TVs accept a close, non-native CVT timing without issue, but a few strict ones may reject it (see below).

```bash
# List outputs and check if the external display is detected
sudo -u kiosk DISPLAY=:0 XAUTHORITY=/home/kiosk/.Xauthority xrandr

# Look for your output (e.g. HDMI1/HDMI2/HDMI-1) as "connected" with a mode list.

# Check what the mirroring logic actually did (native mode vs. forced CVT mode, or failures)
journalctl | grep "KIOSK:" | tail -20

# Check whether the hotplug handler fired
sudo journalctl -u kiosk-hotplug.service -n 20

# Manually re-trigger it
sudo systemctl start kiosk-hotplug.service

# Run the mirroring logic by hand for more verbose output
sudo -u kiosk DISPLAY=:0 XAUTHORITY=/home/kiosk/.Xauthority bash -x /usr/local/bin/kiosk-mirror-display.sh
```
If the output shows `disconnected`, it's a cabling/port/EDID issue, not software — try a different cable/port or a monitor known to work.

If a forced CVT mode is rejected by the display (blank screen only after mirroring runs, works fine before), that display's EDID doesn't accept out-of-spec timings — you'll need to manually pick one of its natively listed modes instead:
```bash
sudo -u kiosk DISPLAY=:0 XAUTHORITY=/home/kiosk/.Xauthority xrandr --output HDMI2 --mode 1360x768 --same-as eDP1
```

**No sound over HDMI (audio only from laptop/built-in speakers):**

Whenever an external display is connected/mirrored, `kiosk-audio-route.sh` switches PipeWire's default sink to whichever sink's name contains `hdmi`, and moves any already-playing audio stream onto it. It's called at kiosk login (after PipeWire is confirmed ready) and by `kiosk-hotplug.service` on every plug/unplug — see `/usr/local/bin/kiosk-mirror-display.sh` above for the display side of the same hotplug event.

```bash
# List sinks and confirm an HDMI one exists (name will contain "hdmi")
sudo -u kiosk pactl list sinks short

# Check what the routing logic actually did
journalctl | grep "KIOSK: audio routed\|KIOSK: failed to route" | tail -10

# Check current default sink
sudo -u kiosk pactl get-default-sink

# Manually re-trigger routing
sudo systemctl start kiosk-hotplug.service

# Force it by hand if needed (replace with your sink name from the list above)
sudo -u kiosk pactl set-default-sink alsa_output.pci-0000_00_1f.3.hdmi-stereo
```
If no sink name contains `hdmi`, the audio codec on that HDMI port either isn't exposed by ALSA/PipeWire on this hardware, or the monitor/TV doesn't report HDMI audio support in its EDID (common on monitors that only do video) — in that case there's no PipeWire-side fix, audio has to come from the laptop speakers or a separate cable.

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
./ubuntu-based-kiosk.sh

# Menu structure:
# 1. Core Settings - Sites, WiFi, schedules, passwords, full reinstall, complete uninstall
# 2. Addons - Authelia Auto-Login, Easy Asterisk Intercom, LMS, CUPS, VNC, VPNs
# 3. Advanced - Diagnostics, logs, Electron updates, virtual consoles, emergency hotspot
# 4. Restart Kiosk Display
```

### Installing Asterisk Intercom

The Asterisk Intercom addon connects this kiosk as a SIP extension to an
Asterisk server you already have running elsewhere (your own PBX, a
Docker container, another box on the network - anywhere). It installs
and configures Baresip as that extension; it does not install or manage
Asterisk itself.

**Access the addon menu:**
```bash
git clone https://github.com/outis1one/ubuntu-based-kiosk/
cd ubuntu-based-kiosk
./install.sh
# Select: 2) Addons → Asterisk Intercom (SIP Extension)
```

**What you'll be asked for** (must match what's already configured on
the Asterisk server): server IP/hostname, SIP port (default 5060, or
5061 if you enable TLS), extension number, SIP password, and whether to
auto-answer incoming calls (intercom mode) or ring for manual answer.

**Managing the client:**
```bash
# Check status (as the kiosk user)
sudo -u kiosk systemctl --user status baresip

# Restart
sudo -u kiosk systemctl --user restart baresip

# View logs
sudo -u kiosk journalctl --user -u baresip -f

# Reconfigure or uninstall
./install.sh
# Select: 2) Addons → Asterisk Intercom (SIP Extension)
```

**Installation location:**
- Baresip config: `~kiosk/.baresip/` (`accounts`, `config`)
- systemd user unit: `~kiosk/.config/systemd/user/baresip.service`

**Not covered here:** standing up the Asterisk PBX server itself. The
legacy `ubuntu-based-kiosk.sh` still offers a Server/Full option that
downloads and runs a third-party installer from a separate "Easy
Asterisk" repository - that repository has since gone through a major
rework upstream, so it isn't carried forward into this addon. If you
need a PBX, set one up separately (that same legacy option, a
FreePBX/Issabel image, a Dockerized Asterisk, etc.) and point this
addon at it as a plain SIP extension.

### Updating Electron

```bash
# Via menu: Advanced → Manual Electron Update (RECOMMENDED)
# The menu option automatically:
# - Creates backup before updating
# - Shows rollback instructions
# - Handles permissions correctly

# Or manually:
cd /home/kiosk/kiosk-app
sudo -u kiosk npm install electron@latest
sudo systemctl restart lightdm
```

**Rollback if update fails:**

The menu update creates automatic backups in `/home/kiosk/electron-backup-<timestamp>/`

```bash
# 1. Stop display
sudo systemctl stop lightdm

# 2. Find your backup (most recent)
ls -lt /home/kiosk/electron-backup-* | head -1

# 3. Restore backup files (replace timestamp with your backup)
BACKUP=/home/kiosk/electron-backup-<timestamp>
sudo cp $BACKUP/package.json /home/kiosk/kiosk-app/
sudo cp $BACKUP/package-lock.json /home/kiosk/kiosk-app/ 2>/dev/null || true

# 4. Remove failed install and reinstall previous version
sudo rm -rf /home/kiosk/kiosk-app/node_modules/electron
cd /home/kiosk/kiosk-app && sudo -u kiosk npm install --unsafe-perm

# 5. Fix permissions
sudo chown root:root /home/kiosk/kiosk-app/node_modules/electron/dist/chrome-sandbox
sudo chmod 4755 /home/kiosk/kiosk-app/node_modules/electron/dist/chrome-sandbox

# 6. Restart display
sudo systemctl start lightdm
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

#### Why Use Named Sites?

Named sites provide user-friendly labels that make navigation and management easier, especially when dealing with multiple similar URLs or complex web addresses.

**Benefits:**

- **Easier Navigation:** Click "Photo Gallery" instead of remembering "https://immich.mydomain.com:2283"
- **Better Organization:** Quickly identify sites in the navigation menu without parsing URLs
- **User-Friendly:** Non-technical users can find sites by name instead of domain
- **Cleaner Display:** "Home Assistant" is more readable than "http://192.168.1.50:8123"
- **Professional Appearance:** Business kiosks benefit from descriptive names over technical URLs

**Use Cases:**

**Home/Family Kiosks:**
- "Photo Albums" instead of "https://photoprism.local:2342"
- "Weather" instead of "https://weather.com"
- "Security Cameras" instead of "http://192.168.1.100:8000"
- "Smart Home" instead of "http://homeassistant.local:8123"

**Business Kiosks:**
- "Employee Portal" instead of "https://portal.company.com/employees"
- "Time Clock" instead of "https://timekeeping.company.com/punch"
- "Inventory System" instead of "http://10.0.0.50:8080/inventory"
- "Customer Service" instead of "https://crm.company.com/support"

**Digital Signage:**
- "Dashboard 1" through "Dashboard 5" for rotating content
- "Announcements" instead of "https://cms.local/public/announcements"
- "Menu Board" instead of "http://192.168.1.75/menus/today"

**Multi-Location Setups:**
- "Building A Reception" and "Building B Reception" for identical URL structures
- "Floor 1 Display" through "Floor 10 Display" for elevator kiosks
- "East Wing" and "West Wing" for hospital navigation

Names are completely optional - if left blank, the URL will be displayed as usual. Configure names during initial setup or update them later via: Core Settings → Sites → Update site names.

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
./ubuntu-based-kiosk.sh
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



---

## Ubuntu Based Kiosk Project License

The Ubuntu Based Kiosk installer script and original code components are licensed under **GPL-3.0-or-later**.

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

## Modular Management (new, in progress)

The 12,000+ line single-file installer works, but every menu lives in the
same file as everything else, which makes small changes risky. We're
pulling the *menu system* out into small, independently editable files as
groundwork for the planned web-based GUI (same modules will back both the
terminal menu and the web UI, so they can't drift apart).

**What's here so far:**
- `lib/menu.sh` — a generic numbered-menu framework (auto-numbers entries,
  always offers `0` to exit/return, validated input helpers). Menu files
  just declare their labels and handler functions; they don't hand-roll
  `echo`/`case` loops.
- `lib/config.sh` — the single place that reads/writes `config.json`.
- `menus/sites.sh` — **Sites & Page Timing**, fully migrated: add, edit,
  delete, and reorder pages, and set the duration/timing mode
  (auto-rotate / manual / hidden) and home page — as a working proof of
  concept for this approach.
- `menus/display.sh` — **Display & Interaction**: touch gesture mode,
  link navigation security, and the on-screen pause/keyboard/navigation
  button toggles. A different menu shape from Sites (settings toggles
  vs. list CRUD).
- `menus/timezone.sh` — **Timezone**: also replaces the legacy script's
  hand-numbered 18-entry `case` statement with a plain data list plus one
  handler — the numbering is just `run_menu`'s job now.
- `menus/hidden_pin.sh` — **Hidden Site PIN**: the PIN gating hidden
  pages (`duration: -1` in Sites). A fourth shape again — a flat file,
  not `config.json`.
- `menus/lockout.sh` — **Password Protection & Lockout**: enable/disable,
  change password, inactivity timeout, daily lock time, boot password.
  The password is SHA-256 hashed before it's ever written to disk, same
  as the legacy menu — never stored as plaintext.
- `menus/wifi.sh` — **WiFi**: the riskiest menu so far — rewrites live
  netplan config and, over SSH, can disconnect the session configuring
  it. Preserves the legacy menu's netplan backup, 60-second SSH
  watchdog, and restore-on-failure exactly.
- `menus/power_schedule.sh` — **Power/Display/Quiet Hours**: scheduled
  shutdown (+ RTC wake where available), display on/off, quiet-hours
  audio muting, and an Electron reload timer, each as systemd timers.
  Can power the physical machine off and on a schedule.
- `menus/diagnostics.sh` — **Diagnostics**: system status, log viewing,
  audio diagnostics, network test — 4 of the legacy Advanced menu's 12
  items, all read-only.
- `menus/addon_cups.sh` — **CUPS Printing** (Addons): install,
  reconfigure for network access, complete uninstall (purge). The first
  Addon migrated — genuinely mutates real system state (apt packages,
  `/etc/cups`, ufw) rather than this project's own files.
- `menus/addon_authelia.sh` — **Authelia Auto-Login** (Addons):
  encrypted SSO credentials plus the server-side setup instructions.
  Prompted the `save_config` merge fix above.
- `menus/addon_remote_access.sh` — **Remote Access** (Addons): VNC,
  WireGuard, Tailscale, Netbird. The biggest Addon so far.
- `menus/addon_lms_squeezelite.sh` — **LMS Server / Squeezelite Player**
  (Addons): install/reconfigure/uninstall for an LMS (Lyrion/Logitech
  Media Server) server the kiosk can host, and a Squeezelite player the
  kiosk can run against any LMS server on the LAN. Squeezelite's own
  start script and systemd unit go through `$BIN_DIR`/`$SYSTEMD_DIR`
  like every other addon; LMS's own apt repo/GPG key/ufw rules stay at
  their real fixed system paths, same as CUPS.
- `menus/addon_asterisk_intercom.sh` — **Asterisk Intercom** (Addons):
  installs Baresip and registers this kiosk as a SIP extension against
  an Asterisk server you already have running elsewhere. Redesigned
  during migration, not a straight port — see "Recent Updates (v2.10.0)"
  below for why the legacy Server/Full PBX-install options didn't come
  along.
- `menus/advanced_electron.sh` — **Electron Maintenance** (Advanced):
  manual update (with backup + rollback) and "fix blank screen" binary
  repair, combined into one submenu since both share the same
  binary-verification logic.
- `menus/advanced_factory_reset.sh` — **Factory Reset** (Advanced):
  wipes `config.json` back to defaults; addons are untouched.
- `menus/advanced_virtual_consoles.sh` — **Virtual Consoles** (Advanced):
  toggles Ctrl+Alt+F1-F8 terminal login access.
- `menus/advanced_emergency_hotspot.sh` — **Emergency Hotspot**
  (Advanced): auto-starts a WiFi hotspot if no internet is detected 60
  seconds after boot. Its own runtime script/systemd unit go through
  `$BIN_DIR`/`$SYSTEMD_DIR` like every other addon.
- `menus/complete_uninstall.sh` — **Complete Uninstall** (Core
  Settings): the last of the "destructive trio." Composed from every
  addon's own `*_do_uninstall` helper instead of re-implementing
  removal a second time — see "Recent Updates (v2.12.0)" below.
- `menus/clone_settings.sh` — **Clone Settings** (Advanced): export/apply
  the portable parts of `config.json` across several kiosks that should
  share the same settings. New, not a legacy port — deliberately never
  copies machine-bound credentials (Authelia, WireGuard, Asterisk
  Intercom); see "Recent Updates (v2.13.0)" below.
- `lib/electron.sh` — `electron_install_binary()`: verify/download the
  Electron binary and fix `chrome-sandbox` permissions. Shared between
  fresh provisioning and `menus/advanced_electron.sh`'s "Fix blank
  screen" action — the same repair sequence applies whether the binary
  never downloaded during the initial `npm install` or went missing
  later.
- `lib/provision.sh` — first-time provisioning: packages, kiosk user,
  Node.js/Electron, LightDM+Openbox autologin, audio/video/HDMI/
  power-button hardware setup, firewall, then hands off to
  `core_settings_menu` and other already-migrated Advanced actions for
  initial configuration, rather than reimplementing that logic a third
  time. See "Recent Updates (v2.14.0)" below.
- `kiosk-app/` — the Electron app source (`main.js`, `preload.js`, the
  dialog HTML files, `package.json`, `start.sh`), copied to the kiosk
  directory during provisioning and re-copied during Upgrade.
- `provision/files/` — every other system template file provisioning
  installs (X11 configs, udev rules, systemd units, the power-button
  and HDMI-mirroring scripts, polkit rules), laid out mirroring their
  real destination path, e.g. `provision/files/etc/X11/xorg.conf.d/
  foo.conf` installs to `/etc/X11/xorg.conf.d/foo.conf`.
- `menus/advanced_upgrade.sh` — **Upgrade** (Advanced): `git pull` (only
  as a clean fast-forward) plus re-running the same
  packages/kiosk-app/display/firewall/power-management provisioning
  steps, so any code or hardware-config change picked up by the pull
  actually takes effect. Also offers an on-demand Electron version
  check. See "Recent Updates (v2.15.0)" below.
- `install.sh` — entry point for the modular tool, now grouped **Core
  Settings / Addons / Advanced** like the legacy menu. On a machine
  with no kiosk installed yet, it provisions one first (see
  `lib/provision.sh` above); on an already-installed kiosk, it goes
  straight to the same menus:
  ```bash
  git clone https://github.com/outis1one/ubuntu-based-kiosk/
  cd ubuntu-based-kiosk
  ./install.sh
  ```

**Honest status:** first-time installation and Upgrade are now covered —
`install.sh` provisions a kiosk from a bare Ubuntu Server box, not just
an already-installed one, and can pull/apply its own updates — but
`ubuntu-based-kiosk.sh` is still ~12,000 lines and still contains its
own unremoved, unmodified copies of every menu above, including the
legacy three-option (Client/Server/Full) Easy Asterisk Intercom — the
modular version only replaces the Client option, by design. One piece
remains legacy-only: Full Reinstall, coupled to
`ubuntu-based-kiosk.sh`'s own heredoc self-extraction of
main.js/preload.js/etc — a different mechanism from the new
provisioning, which copies real files from `kiosk-app/` and
`provision/files/` instead. The legacy Export/Import Settings is also
staying as-is; Clone Settings is a new, narrower feature alongside it,
not a replacement for it — see "Recent Updates (v2.13.0)" below for why
they're not the same thing.
Both copies coexist deliberately: the old ones stay until enough of
Core Settings/Addons/Advanced is migrated to retire them in one pass,
rather than leaving the legacy menu half-wired.

**Resolved (v2.9.0):** `is_service_enabled()` — shared by both scripts
— had a pre-check (`systemctl list-unit-files | grep -q "^${service}\s"`)
that never actually matched, since every call site passes a bare
service name while `list-unit-files` lines start with
`"$service.service"`. The function always fell through to `return 1`
regardless of the real enabled state — under-reporting "enabled but not
currently running" as "not installed" everywhere it's used, including
LMS/Squeezelite's own status detection. Fixed in both `lib/config.sh`
and `ubuntu-based-kiosk.sh` by dropping the dead pre-check —
`systemctl is-enabled` already reports "not found" as a failure on its
own.

**Resolved (v2.7.0):** the config-clobbering bug fixed in `lib/config.sh`
(v2.6.0 — `save_config` silently deleting fields it doesn't know about,
like Authelia's credentials, on the next unrelated save) had the exact
same shape in `ubuntu-based-kiosk.sh`'s own `save_config`. Backported
just that one fix into the legacy script, independent of migrating the
rest of that menu — it was a real credential-loss bug in the
currently-shipping single-file installer and didn't need to wait for a
full migration pass.

---

## Project Status & Future Plans

**Current Version:** 2.15.0

**Recent Updates (v2.15.0):**
- **New: Upgrade** (Advanced → Upgrade) — not a port of the legacy Upgrade, which re-extracted `main.js`/`preload.js`/etc from its own heredocs on every run. `kiosk-app/` and `provision/files/` are real files in this git checkout now, so the modular Upgrade is `git pull` (after confirming a clean working tree, and only as a fast-forward — never an automatic merge) followed by re-running the same packages/kiosk-app/display/firewall/power-management steps `lib/provision.sh` already has for a fresh install, reused rather than reimplemented. Skips the interactive first-run settings wizard and the "reboot now" prompt.
- Also offers an on-demand Electron version check regardless of whether there was code to pull (Electron isn't versioned by this repo) — reuses the existing, already-tested `action_update_electron` as-is.
- Requires a real git checkout (not the no-git ZIP download option) and a clean working tree; a diverged local history fails the pull cleanly with a clear message rather than attempting an automatic merge.

**Previous (v2.14.0):**
- **`./install.sh` now provisions a kiosk from scratch, not just manages an existing one.** Until now it only worked against an already-installed kiosk — `ubuntu-based-kiosk.sh` was still the only path from a bare Ubuntu Server box to a running one. On a machine with no kiosk-app directory yet, it now installs packages, creates the kiosk user, installs Node.js/Electron, sets up LightDM+Openbox autologin, audio/video/HDMI/power-button hardware handling, and the firewall, then hands off to the same Core Settings menus for initial configuration — matching the legacy script's own install-then-configure flow, on the modular codebase.
- **New: `lib/provision.sh`**, the provisioning steps — built almost entirely by calling menus already migrated below (`core_settings_menu`, emergency hotspot, virtual consoles) instead of reimplementing that configuration logic a third time. Reuse cut it down to roughly 300 lines against the legacy script's ~4,000-line `first_time_install()`.
- **New: `lib/electron.sh`** — `electron_install_binary()`, extracted out of `menus/advanced_electron.sh` so fresh provisioning and the existing "Fix blank screen" action share one implementation instead of two copies of the same repair sequence.
- **New: `kiosk-app/`** (the Electron app source — `main.js`, `preload.js`, the dialog HTML files, `package.json`, `start.sh`) and **`provision/files/`** (every other system template file — X11 configs, udev rules, systemd units, the power-button and HDMI-mirroring scripts, polkit rules), extracted byte-for-byte out of `ubuntu-based-kiosk.sh`'s heredocs into real files, laid out mirroring their real destination paths.
- **Bug found and fixed while writing this:** a bash `set -e` gotcha where testing a multi-statement function as an if-condition (`if ! some_func; then`) silently exempts everything inside that function from `set -e` for the duration of the call — found via direct testing, then swept for elsewhere in the codebase and also fixed in `menus/advanced_electron.sh`'s pre-existing "Fix blank screen" action, which had the same shape.
- **Known, deliberate limitation carried over unchanged:** a few of the extracted system scripts (`start.sh`, `kiosk-hotplug.sh`, the power-button handler) hardcode the username `kiosk` rather than substituting `$KIOSK_USER`, exactly as the legacy script's quoted heredocs always did. Only matters if `$KIOSK_USER` is overridden from its default, which in practice is rare.
- Upgrade and Full Reinstall are still not ported — both are coupled to `ubuntu-based-kiosk.sh`'s own heredoc self-extraction, a different mechanism than the new provisioning (which copies real files, not heredocs). `ubuntu-based-kiosk.sh` remains the way to upgrade/reinstall an existing install for now.

**Previous (v2.13.0):**
- **New: Clone Settings** (Advanced → Clone Settings) — not a port of the legacy Export/Import Settings, a narrower MVP for the "set up one kiosk, then stamp out a dozen more like it" use case. Exports the portable parts of `config.json` (sites, display/touch/navigation, lockout, password protection) to a JSON file; applies that file to any other already-installed kiosk.
- **Deliberately does not copy machine-bound credentials**, because copying them would be actively wrong: Authelia's encrypted password is keyed off `/etc/machine-id` and decrypts to garbage on another machine; a WireGuard private key is a device identity, and reusing one across machines is a peer conflict, not a saving; most Asterisk PBXes reject two simultaneous registrations to the same extension. Applying a profile prints these as an explicit "needs a human" checklist instead of silently skipping or cloning them.
- Records which addons were present at export time and reports which are/aren't present on the target — doesn't install anything itself. Non-interactive addon installation (so applying a profile needs zero prompts — scriptable over SSH to a whole fleet) is a deliberate follow-up, not bundled into this MVP.

**Previous (v2.12.0):**
- **Complete Uninstall migrated** — the last of the "destructive trio." Rather than re-implementing every addon's teardown a second time (the legacy shape — CUPS/VNC/WireGuard/Tailscale/Netbird/LMS/Squeezelite removal all inlined again, independently of each addon's own uninstall action), `menus/complete_uninstall.sh` composes the `*_do_uninstall` helpers each addon already has. Every addon menu with an uninstall action was split into a confirm-and-call wrapper (unchanged from the user's perspective) plus a silent removal helper that both the wrapper and Complete Uninstall call — no duplicated logic anywhere, and if an addon's removal logic changes later, Complete Uninstall picks it up automatically.
- **Important bug found and fixed while composing these:** several `*_do_uninstall` helpers (CUPS's `apt autoremove`/`apt clean`, VNC/WireGuard/Tailscale/Netbird's `apt remove`) had a bare, unguarded `apt` call. Previously this only risked aborting that one menu action if the package was already gone. Composed together as sequential calls inside Complete Uninstall, the same failure would have silently truncated the *entire* uninstall partway through — e.g. the kiosk user might never get removed because an already-uninstalled VPN client's `apt remove` failed first. Guarded all of them with `|| true`.
- Non-addon teardown (kiosk user/files, Node.js, LightDM/Openbox, remaining systemd units/scripts, polkit rules, re-enabling virtual consoles, final package cleanup) stays inline in `menus/complete_uninstall.sh`, since no single addon owns those paths — same as the legacy script.
- Upgrade and Full Reinstall remain in `ubuntu-based-kiosk.sh` only — both are coupled to its own heredoc self-extraction of main.js/preload.js/etc, which has no modular equivalent yet.

**Previous (v2.11.0):**
- **4 more Advanced items migrated**, alongside Diagnostics: **Electron Maintenance** (`menus/advanced_electron.sh` — the legacy "Manual Electron Update" and "Fix Blank Screen" combined into one submenu, since both maintain the same installation and share the binary-repair logic), **Factory Reset** (`menus/advanced_factory_reset.sh` — wipes `config.json` only, addons untouched), **Virtual Consoles** (`menus/advanced_virtual_consoles.sh` — toggles Ctrl+Alt+F1-F8 terminal login), and **Emergency Hotspot** (`menus/advanced_emergency_hotspot.sh` — auto-starts a WiFi hotspot if no internet is detected 60 seconds after boot; its own runtime script and systemd unit now go through `$BIN_DIR`/`$SYSTEMD_DIR` like every other addon's own files).
- That's 8 of the legacy Advanced menu's 12 entries now covered. Not migrated this round: Export/Import Settings (pending a decision on whether to rebuild it around actual paths instead of a hardcoded per-addon step list, or whether the future web UI replaces the need for it) and Fix Squeezelite Audio (small enough that it may fold into the LMS addon instead of staying standalone — not decided yet).
- Complete Uninstall (the last of the "destructive trio") is next, composed from each addon's own uninstall action plus core teardown rather than rewriting removal logic a second time. Upgrade and Full Reinstall stay in the legacy script for now — both are coupled to its own heredoc self-extraction of main.js/preload.js/etc, which has no modular equivalent yet.

**Previous (v2.10.0):**
- **Asterisk Intercom migrated, and redesigned in the process.** The legacy addon offered Client Only (Baresip SIP client), Server Only, and Full (server + client) — the latter two downloaded and ran a third-party installer from a separate "Easy Asterisk" repository to stand up a whole Asterisk PBX. That repository has since gone through a major rework upstream, so the PBX-install path is dropped entirely rather than carrying a dependency on code that's moved on without it. The migrated addon (`menus/addon_asterisk_intercom.sh`) now does only the client/endpoint piece: install Baresip and register this kiosk as one SIP extension against an Asterisk server you already have running elsewhere. It never installs or manages Asterisk itself. The legacy script's own three-option version is untouched, same as every other migrated menu.
- Dropped the dependency on the (now-reworked) Easy Asterisk repo's GitHub API for version tracking — reads the real installed `baresip` package version via `dpkg` instead.
- **New capability:** an uninstall option for the Baresip client — the legacy addon never had one.
- **Bug fix:** an unguarded `ver=$(baresip_installed_version)` assignment would have crashed the whole session the first time status was checked before Baresip was installed (`dpkg-query` legitimately fails when the package isn't there). Guarded with `|| true` before it shipped.

**Previous (v2.9.0):**
- **LMS Server / Squeezelite Player migrated** — install/reconfigure/uninstall for both, in `./install.sh`. Squeezelite's own start script and systemd unit now go through `$BIN_DIR`/`$SYSTEMD_DIR` like every other addon instead of hardcoded `/usr/local/bin`/`/etc/systemd/system`; LMS's own apt repo/GPG key/ufw rules stay at their real fixed system paths, same approach as CUPS.
- **Bug fix:** the legacy `install_lms()` enabled/started the detected service via `sudo systemctl enable "$service_name" 2>&1 | tee /tmp/lms-enable.log` — piped through `tee`, the statement's exit status reflected `tee` (always 0), not `systemctl enable`, so a real enable/start failure was silently swallowed instead of falling through to a warning. Now uses the shared `enable_and_start_units()` helper.
- **Bug fix (shared, backported to the legacy script too):** `is_service_enabled()`'s pre-check never matched a bare service name against `list-unit-files`' `"$service.service"` lines, so it always reported "not enabled" regardless of the real state. Dropped the dead pre-check — see "Modular Management" below.

**Previous (v2.8.0):**
- **Remote Access migrated** — VNC, WireGuard, Tailscale, and Netbird, each with its own install/connect/status/uninstall flow. The biggest Addon so far. Tailscale/Netbird install via the vendors' own `curl | sh` method, preserved as-is.
- **Important framework-level bug found and fixed:** `run_menu()`'s *handler* call has been crash-guarded since v2.1.0, but its *status function* call was still completely bare. A status function is meant to be read-only display, but a pipeline whose `grep` matches nothing (which `pipefail` turns into a failure even though the actual last command succeeds) would crash the **entire session**, not just fail to show status. Found while building `wireguard_status()` and verifying its exact failure mode rather than assuming it was covered. Fixed once, in the framework, protecting every status function across every menu — present and future. Also audited every existing status function for the same shape and fixed one real instance in `power_schedule_status()`.
- Deduplicated: promoted `power_schedule.sh`'s `enable_and_start_timers()` to a shared `enable_and_start_units()` in `lib/menu.sh` (works for services now, not just timers) rather than writing the same helper a second time for VNC/WireGuard.

**Previous (v2.7.0):**
- **Backported fix:** `ubuntu-based-kiosk.sh`'s own `save_config()` had the identical config-clobbering bug fixed in `lib/config.sh` under v2.6.0 — it silently deleted Authelia credentials (or any field it doesn't explicitly know about) the next time Sites, Touch Controls, Navigation, or Password Protection saved. This was a real, currently-shipping credential-loss bug, so it's fixed directly in the legacy script now rather than waiting for those menus to be migrated. Verified in isolation against the exact extracted function before touching the shipping copy. Nothing else about those menus changed.

**Previous (v2.6.0):**
- **Authelia Auto-Login migrated** — encrypted SSO credentials (same AES-256-CBC/scrypt algorithm `main.js` decrypts with, verified by a real encrypt→decrypt round trip in testing) plus the full server-side Docker setup instructions, viewable again later without reconfiguring.
- **Important bug found and fixed, not specific to Authelia:** `save_config()` did a full rebuild of `config.json` from known fields — exactly like the legacy script's `save_config` still does. Authelia's own write is a careful merge that preserves everything else, but the *next* save from Sites, Touch Controls, Navigation, or Password Protection would silently delete the Authelia credentials, since none of those knew the three Authelia fields existed. **This is a real bug in the currently-shipping single-file installer**, not introduced by this migration. Fixed in `lib/config.sh` by changing `save_config` to merge its known fields onto whatever's already on disk instead of rebuilding from nothing, so any untracked field — Authelia's three today, anything else tomorrow — survives automatically. The equivalent bug still exists, unfixed, in `ubuntu-based-kiosk.sh`'s own `save_config` — see "Modular Management" below.

**Previous (v2.5.0):**
- **First Addon migrated:** CUPS Printing — install/reconfigure/complete uninstall, in `./install.sh`. Genuinely mutates real system state (`apt install`/`remove --purge`, `/etc/cups`, `ufw`) at fixed paths CUPS itself doesn't let us relocate, so every test uses full command-level `sudo` stubbing rather than the scratch-directory approach used for this project's own files.
- **Menu restructured:** `install.sh`'s top level is now grouped Core Settings / Addons / Advanced, matching the legacy tool, instead of one flat list — done now while it's cheap, ahead of the list getting unwieldy.
- **Bug fix:** a "wait for service to start" retry loop used a bare `cmd1 && cmd2 && break` as its body — that's not made safe by being inside a loop; a bare `&&`/`||` list used as a standalone statement is fully subject to `set -e`, and the first command failing on an early iteration (near-certain right after a fresh install) would have killed the whole session. Restored the `if cmd1 && cmd2; then break; fi` form.
- **Resolved:** real uncertainty about how far `run_menu`'s `handler || true` guard (added in v2.1.0) actually reaches — confirmed with an isolated test that it protects against a failing command no matter how many function calls deep, so the session-crash risk chased since v2.1.0 is already covered end-to-end by that one fix. Per-statement guards still matter for a different reason: without them, a deep failure bubbles past the menu actually responsible for it to wherever the nearest `|| true` happens to catch it.

**Previous (v2.4.0):**
- **Diagnostics migrated** — system status, log viewing (Electron/LightDM/journal), an 8-step audio diagnostic, and a ping+DNS network test, from the legacy Advanced menu. A change of pace: everything here is read-only, no destructive-action risk to manage.
- **Bug fix (set -e safety):** every diagnostic whose failure is the expected case — no lightdm running, no audio hardware, no network, missing logs, `ping`/`nslookup` not even installed — was a bare unguarded statement that would have crashed the whole session instead of reporting "not found" and moving on. Fixed throughout; a diagnostics tool has to survive exactly the broken states it exists to diagnose.
- Manual Electron Update, Factory Reset, Export/Import Settings, Emergency Hotspot, and Fix Blank Screen are staying in the legacy script for now — destructive/mutating, and some share Upgrade's coupling to the legacy script's self-extraction mechanism (see v2.3.0 notes).

**Previous (v2.3.0):**
- **WiFi and Power/Display/Quiet Hours migrated** — by far the riskiest menus tackled so far. WiFi rewrites live netplan config and, over SSH, can disconnect the session configuring it; power scheduling can shut the physical machine down and wake it via RTC. Every legacy safety mechanism is preserved exactly: netplan backup, 60-second SSH watchdog, restore-on-failure for WiFi; RTC availability detection for power scheduling.
- **Bug fix:** the legacy menu refused to open "Configure power schedule" at all without RTC hardware, even though shutdown-only scheduling never needed it.
- **Bug fix:** none of the six HH:MM time prompts across these menus were format-validated before — a typo silently produced a broken schedule. All now go through the same `ask_time` validator as everywhere else.
- **Bug fix (set -e safety):** several more bare statements whose failure would have killed the entire session — `ls *.yaml` with no netplan file present, the backup-restore reapply after a failed `netplan apply`, and `systemctl enable`/`start` after writing each timer pair. The last was only caught by testing without a live systemd; a real failure on actual hardware would have hit the same crash. All now report a warning and return to the menu.
- Deliberately **not** migrated: the legacy "Test schedules & system" option, which leads into a shared diagnostics submenu (audio/network/keyboard tests) unrelated to scheduling — that belongs with a future Advanced/Diagnostics pass.

**Previous (v2.2.0):**
- **Fifth menu migrated:** Password Protection & Lockout (`menus/lockout.sh`) — enable/disable, change password, inactivity timeout, daily lock time, boot password. The password is SHA-256 hashed before it's ever written to `config.json` (matching the Electron app's own comparison logic) — verified never stored as plaintext.
- **Bug fix:** `lib/menu.sh` was missing `ask_time`/`validate_time` entirely — caught by testing this menu before it shipped; "set a daily lock time" would otherwise have failed for every user. Ported from the legacy script.
- **Refactor:** promoted the ON/OFF toggle-label helper out of `menus/display.sh` into a shared `onoff()` in `lib/menu.sh`, so `menus/lockout.sh` doesn't need to depend on another menu file — menus only ever depend on `lib/`.

**Previous (v2.1.0):**
- **Two more menus migrated:** Timezone (`menus/timezone.sh`) and Hidden Site PIN (`menus/hidden_pin.sh`), joining Sites & Page Timing and Display & Interaction in `./install.sh`. Timezone also replaces the old hand-numbered 18-entry list with a data-driven one built on the generic menu framework.
- **Bug fix (framework-level):** `install.sh` runs under `set -e`; a menu action that legitimately fails (e.g. rejecting an invalid timezone) and returns non-zero as its last statement could take down the *entire* session instead of just that action. Caught by testing before this ever shipped broadly; `run_menu()` now absorbs a failed handler's exit code, protecting every menu — present and future.
- The old, unmigrated `configure_sites`/`configure_touch_controls`/`configure_navigation_security`/`configure_optional_features` in `ubuntu-based-kiosk.sh` are staying in place for now (still carrying the v2.0.0 bugs below) until enough of Core Settings/Addons/Advanced is migrated to retire them in one pass — see "Modular Management" below for exactly what's covered so far.

**Previous (v2.0.0):**
- **Modular management path:** new `lib/menu.sh` (reusable numbered-menu framework: auto-numbered entries, `0` always exits/returns) and `lib/config.sh` (single load/save for `config.json`), with menus migrating into `menus/*.sh` one at a time — **Sites & Page Timing** and **Display & Interaction** are migrated so far. Run via `./install.sh` after cloning the repo, against an already-installed kiosk (see "Modular Management" below). Groundwork for the planned web-based GUI, which will share this same `lib/config.sh` layer.
- **Bug fix:** the old Sites menu could save `config.json` without first loading swipe/navigation/lockout settings, silently resetting them to script defaults.
- **Bug fix:** reordering sites had an off-by-one that left the moved site one slot short of the requested position.
- **Renamed installer:** the main script is now `ubuntu-based-kiosk.sh` (no version number in the filename), updated in place going forward. Released versions are tracked via git history and this changelog instead of the filename; older `ubuntu-based-kiosk-v*.sh` / `install_kiosk_*.sh` files remain in the repo as archived releases.

**Previous (v1.0.3):**
- **HDMI/external display mirroring:** any connected display beyond the primary (e.g. HDMI-out to a monitor/TV) is now mirrored automatically at the primary's exact resolution — generating a custom `cvt` mode if the external display doesn't natively list it — both at kiosk login/boot and live on plug/unplug via a new udev-triggered `kiosk-hotplug.service`. Previously the external output was left inactive even when detected by X, and would otherwise mirror at its own native resolution instead of matching the kiosk panel
- **HDMI audio routing:** audio now follows the same hotplug event — the default PipeWire sink automatically switches to the HDMI audio output when an external display is connected/mirrored, and back to the built-in sink when it's disconnected (`kiosk-audio-route.sh`)
- **Package install:** installer now also installs `net-tools` and `ncdu` (alongside the already-installed `curl` and `git`)
- **Touch input fix (keyring):** added `--password-store=basic` to the Electron launch. Under LightDM autologin the GNOME keyring stays locked; when Chromium accessed it, the keyring unlock dialog grabbed all keyboard/touch input — the kiosk rendered fine but ignored every tap and keypress. This flag stops Electron from using the keyring, so the dialog never appears.
- **Touch gesture fix (libinput):** any touch screen is now forced to the `libinput` driver via `/etc/X11/xorg.conf.d/99-finger-libinput.conf` (matched by hardware capability, so it works on any brand and never affects keyboards, mice, or the pen/stylus). Some drivers — notably `wacom` — only do single-touch pointer emulation and never pass real multitouch to Chromium, so 1-finger and 2-finger swipe gestures could not fire. libinput delivers proper multitouch.
- **Upgrade reliability:** `start.sh` is now refreshed on every upgrade alongside `main.js` and `preload.js`
- **Upgrade fix:** node_modules no longer wiped during upgrade — preserves the ~120MB Electron binary so upgrades don't fail on slow/unreliable connections
- **Authelia fix:** 10-second timeout on Authelia login fetch prevents white screen when Authelia is slow to respond
- **Authelia config:** clearer YAML merge instructions with before/after examples to prevent duplicate `access_control:` block mistake
- **Upgrade fix:** config backup cleanup now uses `sudo rm` to avoid "Operation not permitted" error

**Previous (v1.0.2):**
- **Authelia Auto-Login addon** (`Addons → 5`) — authenticates with Authelia SSO on every startup; password stored encrypted (AES-256 keyed from machine ID, not plain text); prints full Dockerized Authelia server-side setup after configuration
- **Bug fix:** PipeWire config dirs were created as root at step [5.5/27], causing "Permission denied" on fresh installs
- **README:** install commands no longer hardcode version numbers — always fetch latest from GitHub

**Previous (v1.0.1):**
- **Node.js upgrade:** 20 LTS → 22 LTS
- **Electron upgrade:** v39/41 → v42.x

**Previous (v1.0.0):**
- **Upgrade fix:** file extraction now correctly verifies written files on Ubuntu 22.04+ systems where the kiosk home directory has restrictive permissions (750)
- **Install fix:** sudo credentials primed upfront before the long apt install step, preventing cache expiry at the timezone prompt
- **Timezone fix:** fallback to direct `/etc/localtime` symlink when `timedatectl` fails via D-Bus

**Previous (v0.9.9.1):**
- Silent upgrade: no user input required, extracts files directly from script
- Power button fixes
- Import allows selecting backup by number instead of typing path

**Previous (v0.9.8):**
- Easy Asterisk Intercom addon with automatic updates
- Smart version detection and configuration preservation
- Named websites feature for user-friendly site identification
- Navigation menu with key icon

**Planned Features:**
- Web-based GUI configuration interface
- All-in-one ISO installer
- Enhanced Raspberry Pi support and testing

**Known Limitations:**
- Raspberry Pi support untested in production
- No web-based configuration (CLI menu only)
- Extended desktop not supported — additional connected displays (e.g. HDMI-out to a monitor/TV) are automatically **mirrored**, not extended

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

- **Repository:** https://github.com/outis1one/ubuntu-based-kiosk/
- **Issues:** https://github.com/outis1one/ubuntu-based-kiosk/issues
- **Discussions:** https://github.com/outis1one/ubuntu-based-kiosk/discussions

---

## Credits

Built with assistance from **Claude Sonnet 4.6** (Anthropic AI)

Special thanks to the maintainers of all upstream projects that make Ubuntu Based Kiosk possible.

---

*Last Updated: June 15, 2026*
*Version: 1.0.3*
