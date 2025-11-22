# UBK Intercom Setup - Mumble/Talkkonnect

This is a standalone script for setting up push-to-talk (PTT) intercom functionality for the Ubuntu Based Kiosk using Mumble/Talkkonnect.

## How to Use

### Option 1: Via Main Install Script (Recommended)
If you've cloned or downloaded the UBK repository, the intercom setup is automatically available:

```bash
# Run the main UBK installer
./install_kiosk_0.9.6.sh

# Navigate to: Main Menu → Addons Management (option 2)
# Then select: talkkonnect/Murmur Intercom (native audio) (option 4)
```

The main installer will automatically launch `setup_intercom.sh` when you select the intercom option.

### Option 2: Standalone Usage
You can also run the intercom setup script directly:

```bash
# Make sure both scripts are in the same directory
cd /path/to/ubk
./setup_intercom.sh
```

**Important:** Both `install_kiosk_0.9.6.sh` and `setup_intercom.sh` must be in the same directory for the integration to work.

## What's Included When You Download the Repository

When you clone or download the UBK repository, you get:

```
ubk/
├── install_kiosk_0.9.6.sh      # Main UBK installer (has intercom integration)
├── setup_intercom.sh           # Standalone intercom setup & management
├── INTERCOM_README.md          # This file
└── integrate_intercom.sh       # (Optional) Integration helper/documentation
```

Both scripts work together:
- **install_kiosk_0.9.6.sh**: Full UBK installation with integrated intercom support
- **setup_intercom.sh**: Dedicated intercom setup with its own menu system

You don't need to modify anything - just run either script and they'll find each other automatically.

## Overview

The intercom system uses:
- **Murmur**: The Mumble server software (can run on one kiosk)
- **talkkonnect**: A headless Mumble client optimized for push-to-talk

## Use Cases

### 1. All-in-One (Server + Client)
One kiosk acts as both the server and a client. Other devices can connect to it.

```bash
./setup_intercom.sh
# Select option 1: Install All-in-One (Server + Client)
```

### 2. Client Only
Connect to an existing Mumble server (could be another kiosk or external server).

```bash
./setup_intercom.sh
# Select option 3: Install talkkonnect Client Only
# Enter the server IP, port, and credentials
```

### 3. Server Only
Turn a kiosk into a dedicated Mumble server.

```bash
./setup_intercom.sh
# Select option 2: Install Murmur Server Only
```

## Quick Start

### Single Kiosk Setup (Server + Client)

```bash
cd /path/to/ubk
./setup_intercom.sh
```

1. Select **Option 1: Install All-in-One (Server + Client)**
2. Set a SuperUser password (for server administration)
3. Set a server password (clients need this to connect)
4. Set a welcome message
5. Set a username for the talkkonnect client
6. The client will auto-connect to the local server

### Multi-Kiosk Setup

**On the server kiosk:**
```bash
./setup_intercom.sh
# Select option 2: Install Murmur Server Only
# Note the server IP address shown after installation
```

**On each client kiosk:**
```bash
./setup_intercom.sh
# Select option 3: Install talkkonnect Client Only
# Enter the server IP from above
# Port: 64738 (default)
# Enter username and password
```

## Features

### Push-to-Talk
- Default PTT key: **Spacebar**
- Press and hold to transmit audio
- Release to stop transmitting

### Management
The script provides a full-featured menu for:
- Starting/stopping services
- Reconfiguring settings
- Viewing logs
- Uninstalling components

### Connecting from Other Devices

Other devices can connect to your Mumble server using:

**Desktop (Windows/Mac/Linux):**
- Download Mumble client: https://www.mumble.info/downloads/
- Connect to: `<kiosk-ip>:64738`

**Mobile (iOS/Android):**
- Install Mumble app from app store
- Add server: `<kiosk-ip>:64738`

## Configuration

### Server Configuration
Location: `/etc/mumble-server.ini`

Key settings:
- Port: 64738 (default)
- Max users: 10
- Bandwidth: 72000

### Client Configuration
Location: `/home/kiosk/talkkonnect.xml`

Key settings:
- Server address and port
- Username and password
- PTT button (default: spacebar)
- Audio settings

## Troubleshooting

### Check Service Status

```bash
# Check Murmur server
sudo systemctl status mumble-server

# Check talkkonnect client
sudo systemctl status talkkonnect
```

### View Logs

Use the built-in menu options, or:

```bash
# Murmur logs
sudo journalctl -u mumble-server -n 50

# talkkonnect logs
sudo journalctl -u talkkonnect -n 50
```

### Audio Issues

1. Check audio devices:
```bash
arecord -l  # List recording devices
aplay -l    # List playback devices
```

2. Test audio:
```bash
# Test microphone
arecord -d 5 test.wav && aplay test.wav
```

3. Edit talkkonnect configuration:
```bash
nano /home/kiosk/talkkonnect.xml
# Adjust <audio> section device names
sudo systemctl restart talkkonnect
```

### Firewall

If clients can't connect, ensure port 64738 is open:

```bash
sudo ufw allow 64738/tcp
sudo ufw allow 64738/udp
```

## Integration with Main Install Script

To integrate this into the main UBK install script:

### Option 1: Direct Integration

Add to the addon menu in `install_kiosk_*.sh`:

```bash
# In the addon menu section
echo "  X. Intercom (Mumble/Talkkonnect)"

# In the case statement
X)
    # Source and run the intercom script
    bash setup_intercom.sh
    ;;
```

### Option 2: Call as External Script

```bash
# From anywhere in the install script
if [[ -f "$SCRIPT_DIR/setup_intercom.sh" ]]; then
    bash "$SCRIPT_DIR/setup_intercom.sh"
else
    echo "Intercom setup script not found"
fi
```

### Option 3: Function Import

Source the functions for use in the main script:

```bash
# Source the intercom functions (requires extracting functions to separate file)
source "$SCRIPT_DIR/intercom_functions.sh"

# Then call functions directly
install_murmur_and_talkkonnect
```

## Technical Details

### Murmur Server
- Package: `mumble-server`
- Service: `mumble-server.service`
- Port: 64738 (TCP/UDP)
- Config: `/etc/mumble-server.ini`
- Database: `/var/lib/mumble-server/mumble-server.sqlite`

### talkkonnect Client
- Written in: Go
- Built from: https://github.com/talkkonnect/talkkonnect
- Binary: `/home/kiosk/go/bin/talkkonnect`
- Service: `talkkonnect.service`
- Config: `/home/kiosk/talkkonnect.xml`

### Dependencies
- Go 1.23.4+
- libopenal-dev
- libopus-dev
- alsa-utils
- portaudio19-dev
- git

## Network Requirements

- **Server**: Port 64738 (TCP/UDP) must be accessible
- **Clients**: Outbound access to server on port 64738
- **Local Network**: For LAN-only intercom, no internet required
- **Remote Access**: If connecting over internet, configure port forwarding

## Security Considerations

1. **Server Password**: Set a strong server password to prevent unauthorized access
2. **SuperUser Password**: Keep this secure - it has admin privileges on the server
3. **Network**: Consider using a VPN for remote access instead of exposing port 64738 to the internet
4. **Certificates**: For production, consider setting up SSL/TLS certificates (currently using `insecure: true`)

## Version History

- **v1.0.0** - Initial standalone release
  - Full Murmur server installation
  - talkkonnect client installation
  - All-in-one option
  - Service management
  - Configuration tools

## Support

For issues or questions:
- Check logs using the built-in menu options
- Review the Troubleshooting section
- Check talkkonnect documentation: https://github.com/talkkonnect/talkkonnect
- Check Mumble documentation: https://wiki.mumble.info/
