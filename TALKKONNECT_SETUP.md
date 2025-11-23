# TalkKonnect Mumble Client Setup Guide

This guide will help you set up TalkKonnect as a headless Mumble client on your kiosk.

## The Permission Issue (FIXED)

The original installation script had a bug where it created the configuration directory in the script runner's home directory instead of the target user's home directory. This caused a "permission denied" error when the service tried to run.

**The fix has been applied to `talkkonnect_complete_install.sh`**

## Quick Fix for Existing Installations

If you already ran the installation and got the permission error, run this:

```bash
sudo ./fix_talkkonnect_permissions.sh
```

This will:
- Move the config to the correct user's home directory
- Fix all file permissions and ownership
- Verify your systemd service configuration

## Fresh Installation

For a new installation, simply run:

```bash
./talkkonnect_complete_install.sh
```

When prompted, enter the username that should run talkkonnect (e.g., `user` or `kiosk`).

The script will now:
1. Install all dependencies
2. Build talkkonnect with the correct Opus library fixes
3. **Create the config in the TARGET user's home directory** (FIXED)
4. **Set proper ownership and permissions** (FIXED)
5. Set up the systemd service to run as the target user

## Configuration

After installation, edit the configuration file:

```bash
# If you're the target user:
nano ~/.config/talkkonnect/talkkonnect.xml

# If talkkonnect runs as a different user (e.g., 'user'):
sudo nano /home/user/.config/talkkonnect/talkkonnect.xml
```

### Required Settings

Update these fields in the XML:

```xml
<serverandport>your.mumble.server:64738</serverandport>
<username>your_username</username>
<password>your_password</password>
<channel>Root</channel>
```

### Self-Signed Certificates

If your Mumble server uses a self-signed certificate, set:

```xml
<insecure>true</insecure>
```

### Voice Activation vs PTT

**Voice Activation (Default):**
```xml
<voiceactivity enabled="true">
  <settings threshold="0.3" holdtimems="1000" holdtimeoutms="2000"/>
</voiceactivity>
<ptt enabled="false"/>
```

**Push-to-Talk with USB Keyboard:**
```xml
<voiceactivity enabled="false"/>
<ptt enabled="true">
  <usbkeyboard enabled="true" device="/dev/input/event0" keycode="KEY_F13"/>
</ptt>
```

To find your USB keyboard device:
```bash
sudo evtest
```

## Testing

### Manual Test

Before enabling the service, test manually:

```bash
# If running as yourself:
/usr/local/bin/talkkonnect -config ~/.config/talkkonnect/talkkonnect.xml

# If running as a different user (e.g., 'user'):
sudo -u user /usr/local/bin/talkkonnect -config /home/user/.config/talkkonnect/talkkonnect.xml
```

You should see:
- Connection to Mumble server
- Join the specified channel
- No permission errors

### Common Errors

**"permission denied" on config file:**
- Run `./fix_talkkonnect_permissions.sh`
- OR manually: `sudo chown -R user:user /home/user/.config/talkkonnect`

**"unable to unmute" errors:**
- This is usually non-fatal; audio may still work
- Check: `amixer scontrols`

**Connection refused:**
- Check your `<serverandport>` setting
- Verify firewall allows outbound connections on port 64738

**Certificate errors:**
- Set `<insecure>true</insecure>` for self-signed certs

## Systemd Service (if available)

If your system uses systemd:

```bash
# Enable and start
sudo systemctl enable talkkonnect
sudo systemctl start talkkonnect

# Check status
sudo systemctl status talkkonnect

# View logs
journalctl -u talkkonnect -f
```

## Docker/Non-Systemd Environments

If you're running in Docker or without systemd, run talkkonnect directly:

```bash
# Create a simple start script
cat > ~/start-talkkonnect.sh << 'EOF'
#!/bin/bash
/usr/local/bin/talkkonnect -config ~/.config/talkkonnect/talkkonnect.xml
EOF

chmod +x ~/start-talkkonnect.sh

# Run it
./start-talkkonnect.sh
```

Or run in the background:

```bash
nohup /usr/local/bin/talkkonnect -config ~/.config/talkkonnect/talkkonnect.xml > ~/talkkonnect.log 2>&1 &
```

## Audio Configuration

### ALSA (Direct)
Best for single-application use:
```xml
<input>
  <settings enabled="true" device="hw:0,0" samplerate="48000" channels="1"/>
</input>
<output>
  <settings enabled="true" device="hw:0,0" samplerate="48000" channels="1"/>
</output>
```

### PulseAudio/PipeWire
Best for multi-application use:
```xml
<input>
  <settings enabled="true" device="default" samplerate="48000" channels="1"/>
</input>
<output>
  <settings enabled="true" device="default" samplerate="48000" channels="1"/>
</output>
```

List available devices:
```bash
aplay -L        # List output devices
arecord -L      # List input devices
```

## Programmatic Channel Switching

TalkKonnect can join a specific channel on connect by setting:

```xml
<channel>Your/Channel/Path</channel>
```

Use `/` to separate nested channels:
- `Root` - joins root channel
- `General` - joins General channel
- `General/Support` - joins Support subchannel under General

To switch channels at runtime, TalkKonnect has an API you can enable:

```xml
<api enabled="true">
  <listenport>8011</listenport>
</api>
```

Then use HTTP requests to control it:
```bash
# Switch channel
curl http://localhost:8011/api/channel?channel=General/Support
```

## Troubleshooting

### Common Warnings (Usually Non-Fatal)

These warnings often appear but don't prevent talkkonnect from working:

**`Unable to Unmute failed to execute "pactl set-sink-mute 0 0"`**
- TalkKonnect is trying to unmute your audio output
- This usually fails because the sink index is wrong or pactl isn't accessible
- **Audio typically works anyway** - this is just a cosmetic error
- To fix: Run `./fix_talkkonnect_audio.sh` to check your audio configuration

**`Unable to Find Channel Name: Root`**
- Just a warning - connection usually succeeds anyway
- The channel exists but talkkonnect didn't detect it during initial scan
- You'll see a follow-up message showing successful connection

**`Failed to connect PipeWire event context (errno: 112)`**
- TalkKonnect is trying to use PipeWire but can't access the session
- Usually happens when running as a service without proper environment
- **If you see `Speaking ->` messages, audio is working!**
- To fix: Ensure XDG_RUNTIME_DIR is set correctly in systemd service

### Audio Troubleshooting

Run the audio diagnostic script:
```bash
./fix_talkkonnect_audio.sh
```

This will:
- Check PipeWire/PulseAudio session status
- List available audio devices
- Show current talkkonnect configuration
- Provide specific recommendations

**Quick audio test:**
```bash
# Test as the kiosk user (replace with your user)
sudo -u kiosk XDG_RUNTIME_DIR=/run/user/$(id -u kiosk) speaker-test -t wav -c 2 -l 1
```

### View Logs

```bash
# Config file log
cat ~/.config/talkkonnect/talkkonnect.log

# Systemd logs (if applicable)
journalctl -u talkkonnect -f

# Manual run (shows errors directly)
/usr/local/bin/talkkonnect -config ~/.config/talkkonnect/talkkonnect.xml
```

### Common Issues

1. **No audio input/output:**
   - Check `aplay -l` and `arecord -l`
   - Verify user is in `audio` group: `groups`
   - Test audio: `speaker-test` or `arecord -d 5 test.wav && aplay test.wav`

2. **Can't access /dev/input devices (for PTT):**
   - Verify user is in `input` group: `groups`
   - May need to log out and back in after adding to group

3. **Connection drops frequently:**
   - Check network stability
   - Increase keepalive timeouts in config
   - Check server logs

4. **Permissions errors:**
   - Run `./fix_talkkonnect_permissions.sh`
   - Verify config directory ownership: `ls -la ~/.config/talkkonnect`

## Files and Locations

- **Binary:** `/usr/local/bin/talkkonnect`
- **Config:** `~/.config/talkkonnect/talkkonnect.xml`
- **Logs:** `~/.config/talkkonnect/talkkonnect.log`
- **Service:** `/etc/systemd/system/talkkonnect.service` (if using systemd)
- **Source:** `~/talkkonnect`

## Security Notes

- Config file contains your Mumble password in plain text
- Protect it: `chmod 600 ~/.config/talkkonnect/talkkonnect.xml`
- Consider using certificate-based authentication instead of passwords
- For production, use proper systemd hardening options

## Next Steps

1. ✅ Fix permissions (if needed): `./fix_talkkonnect_permissions.sh`
2. ✅ Edit config: `nano ~/.config/talkkonnect/talkkonnect.xml`
3. ✅ Test manually first
4. ✅ Enable systemd service (if applicable)
5. ✅ Configure audio ducking for multi-app environments (optional)
6. ✅ Set up API for programmatic control (optional)

## References

- [TalkKonnect GitHub](https://github.com/talkkonnect/talkkonnect)
- [Mumble Protocol](https://www.mumble.info/documentation/)
- Config file path: `~/.config/talkkonnect/talkkonnect.xml`
