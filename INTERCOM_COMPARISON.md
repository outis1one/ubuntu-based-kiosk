# Intercom Solution Comparison

## Overview

This document compares different Mumble client options for the UBK kiosk intercom system (Phase 2).

## Options Evaluated

### 1. talkkonnect (Current)
- **Repository**: https://github.com/talkkonnect/talkkonnect
- **Type**: Full-featured headless Mumble client
- **Pros**:
  - Very feature-rich
  - Active development
  - Lots of hardware integration options
- **Cons**:
  - Complex build process (Go 1.24+ required, Opus patching needed)
  - Many dependencies
  - Can be fragile on different platforms
  - XML configuration required
  - Heavy for simple use cases

### 2. talkiepi (Recommended)
- **Repository**: https://github.com/dchote/talkiepi
- **Type**: Lightweight barnard-based client
- **Pros**:
  - Simple, clean codebase
  - Easy build process
  - **CLI arguments for all connection params**: `-server`, `-username`, `-password`, `-channel`
  - Based on proven barnard client
  - Fewer dependencies (just Go, libopenal, libopus)
  - More stable and predictable
  - Perfect for headless/kiosk use
- **Cons**:
  - Less features than talkkonnect
  - Focused on simplicity over advanced features
- **Best for**: Intercom use case

### 3. barnard (Original)
- **Repository**: https://github.com/layeh/barnard
- **Type**: Terminal-based interactive client
- **Pros**:
  - Interactive ncurses UI
  - Good for manual/desktop use
  - CLI arguments for server, username, password
- **Cons**:
  - No `-channel` flag (must navigate after connecting)
  - Interactive UI not ideal for automated/headless use
  - Not designed for systemd/autostart scenarios
- **Best for**: Manual desktop use, not kiosk automation

### 4. barnard (bmmcginty fork)
- **Repository**: https://github.com/bmmcginty/barnard
- **Type**: Accessible terminal client for blind users
- **Pros**:
  - Enhanced accessibility features
  - FIFO control for external automation
  - Audio boost capability
  - Config file support
- **Cons**:
  - Still no `-channel` flag
  - Interactive focus
- **Best for**: Accessibility-focused manual use

### 5. mumbler (tmelvin)
- **Repository**: https://github.com/tmelvin/mumbler
- **Type**: CLI client with immediate channel connection
- **Pros**:
  - Supports `-channel` flag
  - `-inmediatestart` for auto-transmission
  - Simple CLI interface
- **Cons**:
  - Password flag support unclear from documentation
  - Less mature/tested
  - Smaller community
- **Best for**: Quick testing, uncertain for production

## Recommendation

**Use talkiepi** for the UBK kiosk intercom project because:

1. ✅ **Simpler** - Much easier to build and maintain than talkkonnect
2. ✅ **Complete CLI** - Has all needed flags: server, username, password, channel
3. ✅ **Stable** - Based on barnard, proven and reliable
4. ✅ **Lightweight** - Minimal dependencies, smaller footprint
5. ✅ **Headless-ready** - Designed for automated/systemd use
6. ✅ **Less fragile** - Fewer moving parts = fewer things to break

## Implementation

Two scripts are provided:

1. **setup_intercom.sh** - Original with talkkonnect
2. **setup_intercom_simple.sh** - New with talkiepi (recommended)

### Quick Start with talkiepi

```bash
# Make executable
chmod +x setup_intercom_simple.sh

# Run the installer
./setup_intercom_simple.sh

# Choose option 1 for all-in-one (server + client)
```

### Manual talkiepi Command

```bash
talkiepi -server 192.168.1.100:64738 \
         -username kiosk \
         -password mypass \
         -channel "Intercom" \
         -insecure
```

## Migration Path

If currently using talkkonnect:

1. Uninstall talkkonnect via setup_intercom.sh
2. Run setup_intercom_simple.sh to install talkiepi
3. Use same Murmur server configuration
4. Enjoy simpler, more reliable setup

## Sources

- [talkiepi GitHub](https://github.com/dchote/talkiepi)
- [talkiepi Documentation](https://github.com/dchote/talkiepi/blob/master/doc/README.md)
- [barnard GitHub](https://github.com/layeh/barnard)
- [mumbler GitHub](https://github.com/tmelvin/mumbler)
- [Mumble Protocol Discussion](https://github.com/mumble-voip/mumble/issues/2595)
