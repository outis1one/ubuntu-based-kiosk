#!/usr/bin/env bash
# ======================================================================
# File: install_talkkonnect_x86_complete.sh
# Purpose: Complete Talkkonnect installation for Ubuntu 24.04 x86_64
#          Fixes Opus architecture issues and creates working config
# Author: Compiled from troubleshooting session
# Date: November 2025
# ======================================================================
set -e

echo "======================================================================="
echo "TalkKonnect Complete Installation Script for x86_64"
echo "This script will:"
echo "  1. Install system dependencies"
echo "  2. Install Go 1.24.1"
echo "  3. Clone and patch TalkKonnect for x86_64"
echo "  4. Build the binary"
echo "  5. Create configuration files"
echo "  6. Set up systemd service"
echo "======================================================================="
echo ""

# Check if this is a Chromebook or multi-user audio setup
echo "Audio Setup Detection:"
echo "  - If you have audio working under a different user (e.g. 'kiosk'),"
echo "    talkkonnect should run as that user to share the PipeWire session"
echo "  - This also enables audio ducking between applications"
echo ""
read -p "Run talkkonnect as a different user? [kiosk]: " TARGET_USER
TARGET_USER=${TARGET_USER:-kiosk}

if [ "$TARGET_USER" != "$USER" ]; then
    # Verify the target user exists
    if ! id "$TARGET_USER" &>/dev/null; then
        echo "[!] Error: User '$TARGET_USER' does not exist"
        exit 1
    fi
    
    # Get target user's UID for XDG_RUNTIME_DIR
    TARGET_UID=$(id -u "$TARGET_USER")
    TARGET_HOME=$(eval echo ~"$TARGET_USER")
    echo "[+] Will install for user: $TARGET_USER (UID: $TARGET_UID)"
    echo "[+] Home directory: $TARGET_HOME"
else
    TARGET_UID=$(id -u)
    TARGET_HOME="$HOME"
    echo "[+] Installing for current user: $USER"
fi

echo ""
read -p "Press Enter to continue or Ctrl-C to abort..."

# --- System Prep ------------------------------------------------------
echo ""
echo "[+] Updating system packages..."
sudo apt update
sudo apt upgrade -y

echo "[+] Installing dependencies..."
sudo apt install -y wget git build-essential pkg-config \
    libasound2-dev libopus-dev libopus0 libopusfile-dev \
    libpipewire-0.3-dev libevdev-dev libopenal-dev alsa-utils

# --- Go Installation --------------------------------------------------
echo ""
echo "[+] Installing Go 1.24.1..."
sudo rm -rf /usr/local/go /usr/lib/go* /usr/bin/go
wget https://go.dev/dl/go1.24.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.24.1.linux-amd64.tar.gz
sudo ln -sf /usr/local/go/bin/go /usr/bin/go
rm -f go1.24.1.linux-amd64.tar.gz
export PATH="/usr/local/go/bin:$PATH"
go version

# --- Clone TalkKonnect ------------------------------------------------
echo ""
echo "[+] Cloning TalkKonnect repository..."
cd ~
if [ -d "talkkonnect" ]; then
    echo "[!] Removing existing talkkonnect directory..."
    rm -rf talkkonnect
fi

git clone https://github.com/talkkonnect/talkkonnect.git
cd talkkonnect

echo "[+] Current version:"
git log --oneline -1

# --- Critical Fix: Patch gopus for x86_64 -----------------------------
echo ""
echo "======================================================================="
echo "[+] APPLYING X86_64 OPUS FIX"
echo "======================================================================="
echo "[+] The talkkonnect gopus package embeds Opus source for ARM"
echo "[+] but it's incomplete for x86_64. We'll patch it to use system libopus"
echo ""

# Create vendor directory
go mod vendor

# Check that gopus exists in vendor
if [ ! -d "vendor/github.com/talkkonnect/gopus" ]; then
    echo "[!] ERROR: gopus not found in vendor!"
    exit 1
fi

echo "[+] Backing up original opus_nonshared.go..."
cp vendor/github.com/talkkonnect/gopus/opus_nonshared.go \
   vendor/github.com/talkkonnect/gopus/opus_nonshared.go.original

echo "[+] Creating x86_64-compatible opus_nonshared.go..."
cat > vendor/github.com/talkkonnect/gopus/opus_nonshared.go << 'EOFOPUS'
// +build amd64,cgo 386,cgo

package gopus

// #cgo pkg-config: opus
// #cgo LDFLAGS: -lm
//
// #include <stdio.h>
// #include <stdlib.h>
// #include <opus.h>
//
// enum {
//   gopus_ok = OPUS_OK,
//   gopus_bad_arg = OPUS_BAD_ARG,
//   gopus_small_buffer = OPUS_BUFFER_TOO_SMALL,
//   gopus_internal = OPUS_INTERNAL_ERROR,
//   gopus_invalid_packet = OPUS_INVALID_PACKET,
//   gopus_unimplemented = OPUS_UNIMPLEMENTED,
//   gopus_invalid_state = OPUS_INVALID_STATE,
//   gopus_alloc_fail = OPUS_ALLOC_FAIL,
// };
//
// enum {
//   gopus_application_voip    = OPUS_APPLICATION_VOIP,
//   gopus_application_audio   = OPUS_APPLICATION_AUDIO,
//   gopus_restricted_lowdelay = OPUS_APPLICATION_RESTRICTED_LOWDELAY,
//   gopus_bitrate_max         = OPUS_BITRATE_MAX,
// };
//
// void gopus_setvbr(OpusEncoder *encoder, int vbr) {
//   opus_encoder_ctl(encoder, OPUS_SET_VBR(vbr));
// }
//
// void gopus_setbitrate(OpusEncoder *encoder, int bitrate) {
//   opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
// }
//
// opus_int32 gopus_bitrate(OpusEncoder *encoder) {
//   opus_int32 bitrate;
//   opus_encoder_ctl(encoder, OPUS_GET_BITRATE(&bitrate));
//   return bitrate;
// }
//
// void gopus_setapplication(OpusEncoder *encoder, int application) {
//   opus_encoder_ctl(encoder, OPUS_SET_APPLICATION(application));
// }
//
// opus_int32 gopus_application(OpusEncoder *encoder) {
//   opus_int32 application;
//   opus_encoder_ctl(encoder, OPUS_GET_APPLICATION(&application));
//   return application;
// }
//
// void gopus_encoder_resetstate(OpusEncoder *encoder) {
//   opus_encoder_ctl(encoder, OPUS_RESET_STATE);
// }
//
// void gopus_decoder_resetstate(OpusDecoder *decoder) {
//   opus_decoder_ctl(decoder, OPUS_RESET_STATE);
// }
import "C"

import (
	"errors"
	"unsafe"
)

type Application int

const (
	Voip               Application = C.gopus_application_voip
	Audio              Application = C.gopus_application_audio
	RestrictedLowDelay Application = C.gopus_restricted_lowdelay
)

const (
	BitrateMaximum = C.gopus_bitrate_max
)

type Encoder struct {
	data     []byte
	cEncoder *C.struct_OpusEncoder
}

func NewEncoder(sampleRate, channels int, application Application) (*Encoder, error) {
	encoder := &Encoder{}
	encoder.data = make([]byte, int(C.opus_encoder_get_size(C.int(channels))))
	encoder.cEncoder = (*C.struct_OpusEncoder)(unsafe.Pointer(&encoder.data[0]))

	ret := C.opus_encoder_init(encoder.cEncoder, C.opus_int32(sampleRate), C.int(channels), C.int(application))
	if err := getErr(ret); err != nil {
		return nil, err
	}
	return encoder, nil
}

func (e *Encoder) Encode(pcm []int16, frameSize, maxDataBytes int) ([]byte, error) {
	pcmPtr := (*C.opus_int16)(unsafe.Pointer(&pcm[0]))

	data := make([]byte, maxDataBytes)
	dataPtr := (*C.uchar)(unsafe.Pointer(&data[0]))

	encodedC := C.opus_encode(e.cEncoder, pcmPtr, C.int(frameSize), dataPtr, C.opus_int32(len(data)))
	encoded := int(encodedC)

	if encoded < 0 {
		return nil, getErr(C.int(encodedC))
	}
	return data[0:encoded], nil
}

func (e *Encoder) SetVbr(vbr bool) {
	var cVbr C.int
	if vbr {
		cVbr = 1
	} else {
		cVbr = 0
	}
	C.gopus_setvbr(e.cEncoder, cVbr)
}

func (e *Encoder) SetBitrate(bitrate int) {
	C.gopus_setbitrate(e.cEncoder, C.int(bitrate))
}

func (e *Encoder) Bitrate() int {
	return int(C.gopus_bitrate(e.cEncoder))
}

func (e *Encoder) SetApplication(application Application) {
	C.gopus_setapplication(e.cEncoder, C.int(application))
}

func (e *Encoder) Application() Application {
	return Application(C.gopus_application(e.cEncoder))
}

func (e *Encoder) ResetState() {
	C.gopus_encoder_resetstate(e.cEncoder)
}

type Decoder struct {
	data     []byte
	cDecoder *C.struct_OpusDecoder
	channels int
}

func NewDecoder(sampleRate, channels int) (*Decoder, error) {
	decoder := &Decoder{}
	decoder.data = make([]byte, int(C.opus_decoder_get_size(C.int(channels))))
	decoder.cDecoder = (*C.struct_OpusDecoder)(unsafe.Pointer(&decoder.data[0]))

	ret := C.opus_decoder_init(decoder.cDecoder, C.opus_int32(sampleRate), C.int(channels))
	if err := getErr(ret); err != nil {
		return nil, err
	}
	decoder.channels = channels

	return decoder, nil
}

func (d *Decoder) Decode(data []byte, frameSize int, fec bool) ([]int16, error) {
	var dataPtr *C.uchar
	if len(data) > 0 {
		dataPtr = (*C.uchar)(unsafe.Pointer(&data[0]))
	}
	dataLen := C.opus_int32(len(data))

	output := make([]int16, d.channels*frameSize)
	outputPtr := (*C.opus_int16)(unsafe.Pointer(&output[0]))

	var cFec C.int
	if fec {
		cFec = 1
	} else {
		cFec = 0
	}

	cRet := C.opus_decode(d.cDecoder, dataPtr, dataLen, outputPtr, C.int(frameSize), cFec)
	ret := int(cRet)

	if ret < 0 {
		return nil, getErr(cRet)
	}
	return output[:ret*d.channels], nil
}

func (d *Decoder) ResetState() {
	C.gopus_decoder_resetstate(d.cDecoder)
}

func GetSamplesPerFrame(data []byte, samplingRate int) (int, error) {
	dataPtr := (*C.uchar)(unsafe.Pointer(&data[0]))
	cSamplingRate := C.opus_int32(samplingRate)
	cRet := C.opus_packet_get_samples_per_frame(dataPtr, cSamplingRate)
	return int(cRet), nil
}

func CountFrames(data []byte) (int, error) {
	dataPtr := (*C.uchar)(unsafe.Pointer(&data[0]))
	cLen := C.opus_int32(len(data))

	cRet := C.opus_packet_get_nb_frames(dataPtr, cLen)
	if err := getErr(cRet); err != nil {
		return 0, err
	}
	return int(cRet), nil
}

var (
	ErrBadArgument   = errors.New("bad argument")
	ErrSmallBuffer   = errors.New("buffer is too small")
	ErrInternal      = errors.New("internal error")
	ErrInvalidPacket = errors.New("invalid packet")
	ErrUnimplemented = errors.New("unimplemented")
	ErrInvalidState  = errors.New("invalid state")
	ErrAllocFail     = errors.New("allocation failed")
	ErrUnknown       = errors.New("unknown error")
)

func getErr(code C.int) error {
	switch code {
	case C.gopus_ok:
		return nil
	case C.gopus_bad_arg:
		return ErrBadArgument
	case C.gopus_small_buffer:
		return ErrSmallBuffer
	case C.gopus_internal:
		return ErrInternal
	case C.gopus_invalid_packet:
		return ErrInvalidPacket
	case C.gopus_unimplemented:
		return ErrUnimplemented
	case C.gopus_invalid_state:
		return ErrInvalidState
	case C.gopus_alloc_fail:
		return ErrAllocFail
	default:
		return ErrUnknown
	}
}
EOFOPUS

echo "[+] Patched opus_nonshared.go to use system libopus"

# --- Build TalkKonnect ------------------------------------------------
echo ""
echo "======================================================================="
echo "[+] BUILDING TALKKONNECT"
echo "======================================================================="
cd ~/talkkonnect/cmd/talkkonnect

export CGO_ENABLED=1
export CGO_CFLAGS="$(pkg-config --cflags opus)"
export CGO_LDFLAGS="$(pkg-config --libs opus) -lm"

echo "[+] Building (this may take a few minutes)..."
go build -mod=vendor -v -o ~/talkkonnect-binary . 2>&1 | tee /tmp/talkkonnect_build.log

if [ ! -f ~/talkkonnect-binary ]; then
    echo ""
    echo "[!] BUILD FAILED!"
    echo "[!] Last 50 lines of build log:"
    tail -50 /tmp/talkkonnect_build.log
    exit 1
fi

echo ""
echo "[+] Installing binary..."

# Stop any running talkkonnect instances first
if systemctl is-active --quiet talkkonnect 2>/dev/null; then
    echo "[+] Stopping existing talkkonnect service..."
    sudo systemctl stop talkkonnect
fi

# Kill any stray processes
if pgrep -x talkkonnect > /dev/null; then
    echo "[+] Killing running talkkonnect processes..."
    sudo pkill -9 talkkonnect
    sleep 1
fi

# Now install the binary
sudo cp ~/talkkonnect-binary /usr/local/bin/talkkonnect
sudo chmod +x /usr/local/bin/talkkonnect
rm ~/talkkonnect-binary

echo "[+] Binary installed successfully!"
echo "[+] Checking dependencies:"
ldd /usr/local/bin/talkkonnect | grep -E "(opus|alsa)" || echo "    (may be statically linked)"

# --- User Permissions -------------------------------------------------
echo ""
echo "[+] Setting up user permissions..."

# Add target user to input group for keyboard PTT
if ! groups "$TARGET_USER" | grep -q input; then
    sudo usermod -a -G input "$TARGET_USER"
    echo "[+] Added $TARGET_USER to 'input' group"
    if [ "$TARGET_USER" = "$USER" ]; then
        echo "[!] IMPORTANT: Log out and back in for this to take effect!"
        echo "[!] Or run: newgrp input"
        NEEDS_RELOGIN=true
    fi
else
    echo "[+] User $TARGET_USER already in 'input' group"
    NEEDS_RELOGIN=false
fi

# Add target user to audio group
if ! groups "$TARGET_USER" | grep -q audio; then
    sudo usermod -a -G audio "$TARGET_USER"
    echo "[+] Added $TARGET_USER to 'audio' group"
fi

# --- Configuration ----------------------------------------------------
echo ""
echo "======================================================================="
echo "[+] CREATING CONFIGURATION"
echo "======================================================================="

CONFIG_DIR="$TARGET_HOME/.config/talkkonnect"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/talkkonnect.xml" << 'EOFXML'
<?xml version="1.0" encoding="UTF-8"?>
<document type="talkkonnect/xml">
  <global>
    <software>
      <settings outputdevice="default" 
                logfilenameandpath="/home/user/.config/talkkonnect/talkkonnect.log" 
                logging="both" 
                daemonize="false" 
                cancelconnect="false" 
                simplexwithvox="false" 
                nextserverindex="0"/>
      <autoprovisioning enabled="false"/>
    </software>
    <hardware>
      <settings targetboard="pc"
                voiceactivitytimersecs="200"/>
      <io>
        <pins enabled="false"/>
      </io>
    </hardware>
  </global>

  <accounts>
    <account name="default" default="true">
      <serverandport>your.mumble.server:64738</serverandport>
      <username>your_username</username>
      <password>your_password</password>
      <insecure>false</insecure>
      <register>false</register>
      <certificate></certificate>
      <channel>Root</channel>
      <ident></ident>
      <tokens enabled="false"></tokens>
      <voicetargets enabled="false">
        <id id="1" iscurrent="false" name="default">
          <channels></channels>
          <users></users>
        </id>
      </voicetargets>
    </account>
  </accounts>

  <beacon enabled="false"/>

  <audio>
    <input>
      <settings enabled="true" 
                device="default" 
                samplerate="48000" 
                channels="1" 
                codec="opus" 
                framespersecond="50"/>
    </input>
    <output>
      <settings enabled="true" 
                device="default" 
                samplerate="48000" 
                channels="1"/>
    </output>
  </audio>

  <ptt enabled="false">
    <usbkeyboard enabled="false"/>
  </ptt>

  <voiceactivity enabled="true">
    <settings threshold="0.3" 
              holdtimems="1000"
              holdtimeoutms="2000"/>
  </voiceactivity>

  <sounds enabled="false"/>
  
  <txtts enabled="false"/>

  <smtp enabled="false"/>

  <api enabled="false"/>

  <printxml enabled="false"/>

</document>
EOFXML

# Update the log path to use actual username
sed -i "s|/home/user/|$TARGET_HOME/|g" "$CONFIG_DIR/talkkonnect.xml"

# Set proper ownership if running as a different user
if [ "$TARGET_USER" != "$USER" ]; then
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$CONFIG_DIR"
    echo "[+] Set ownership of config directory to $TARGET_USER"
fi

echo "[+] Created configuration file: $CONFIG_DIR/talkkonnect.xml"

# --- Audio Mixer Detection --------------------------------------------
echo ""
echo "[+] Detecting audio configuration for user: $TARGET_USER..."

# Detect audio devices as the target user
if [ "$TARGET_USER" != "$USER" ]; then
    # Get target user's runtime directory
    AUDIO_DEVICES=$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$TARGET_UID aplay -l 2>/dev/null)
    PIPEWIRE_SINKS=$(sudo -u "$TARGET_USER" XDG_RUNTIME_DIR=/run/user/$TARGET_UID pactl list sinks short 2>/dev/null)
else
    AUDIO_DEVICES=$(aplay -l 2>/dev/null)
    PIPEWIRE_SINKS=$(pactl list sinks short 2>/dev/null)
fi

# Determine best audio device
AUDIO_DEVICE="default"
AUDIO_BACKEND="alsa"

if echo "$AUDIO_DEVICES" | grep -q "card 0:"; then
    # ALSA devices found
    CARD_NAME=$(echo "$AUDIO_DEVICES" | grep "card 0:" | head -1 | sed 's/.*card 0: \([^[]*\).*/\1/' | xargs)
    echo "[+] Found ALSA card: $CARD_NAME"
    
    # Use hw:0,0 for direct ALSA access (better for Chromebooks)
    AUDIO_DEVICE="hw:0,0"
    echo "[+] Using ALSA device: $AUDIO_DEVICE"
    
elif echo "$PIPEWIRE_SINKS" | grep -v "auto_null" | grep -q "alsa_output"; then
    # PipeWire/PulseAudio sinks found
    SINK_NAME=$(echo "$PIPEWIRE_SINKS" | grep -v "auto_null" | grep "alsa_output" | head -1 | awk '{print $2}')
    echo "[+] Found PipeWire sink: $SINK_NAME"
    AUDIO_DEVICE="pulse"
    AUDIO_BACKEND="pulse"
    echo "[+] Using PulseAudio/PipeWire backend"
else
    echo "[!] Warning: No specific audio device detected, using 'default'"
fi

# Try to unmute and set volume
MIXER_CONTROL=$(sudo -u "$TARGET_USER" amixer scontrols 2>/dev/null | grep -oP "Simple mixer control '\K[^']+(?=',0)" | head -1)

if [ -n "$MIXER_CONTROL" ]; then
    echo "[+] Found mixer control: $MIXER_CONTROL"
    
    # Try to unmute and set volume
    sudo -u "$TARGET_USER" amixer set "$MIXER_CONTROL" unmute 2>/dev/null && echo "[+] Unmuted $MIXER_CONTROL" || echo "[!] Could not unmute $MIXER_CONTROL"
    sudo -u "$TARGET_USER" amixer set "$MIXER_CONTROL" 80% 2>/dev/null && echo "[+] Set $MIXER_CONTROL to 80%" || echo "[!] Could not set volume"
else
    echo "[!] Warning: No ALSA mixer controls found"
    echo "[!] Audio may work through PipeWire, but you may need to configure it manually"
fi

echo "[+] Audio configuration summary:"
echo "    Backend: $AUDIO_BACKEND"
echo "    Device:  $AUDIO_DEVICE"
if [ -n "$CARD_NAME" ]; then
    echo "    Card:    $CARD_NAME"
fi

# --- Systemd Service --------------------------------------------------
echo ""
echo "[+] Creating systemd service for user: $TARGET_USER..."
SERVICE_FILE="/etc/systemd/system/talkkonnect.service"

sudo tee "$SERVICE_FILE" > /dev/null <<EOFSVC
[Unit]
Description=TalkKonnect Headless Mumble Transceiver
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_USER
WorkingDirectory=$TARGET_HOME
ExecStart=/usr/local/bin/talkkonnect -config $CONFIG_DIR/talkkonnect.xml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
# Use target user's PipeWire/PulseAudio session
Environment="XDG_RUNTIME_DIR=/run/user/$TARGET_UID"

[Install]
WantedBy=multi-user.target
EOFSVC

sudo systemctl daemon-reload
sudo systemctl enable talkkonnect

echo "[+] Systemd service created and enabled"

# --- Audio Ducking Setup (Optional) -----------------------------------
if [ "$TARGET_USER" != "$USER" ]; then
    echo ""
    echo "[+] Setting up audio ducking for user: $TARGET_USER..."
    echo "[+] This will lower other audio when talkkonnect is transmitting"
    
    # Create a script to enable ducking
    DUCKING_SCRIPT="$TARGET_HOME/.config/talkkonnect/enable-ducking.sh"
    cat > /tmp/enable-ducking.sh << 'EOFDUCKING'
#!/bin/bash
# Enable audio ducking - lowers music/media when on PTT
pactl load-module module-role-ducking \
    trigger_roles=phone \
    ducking_roles=music,video \
    volume=30% 2>/dev/null || echo "Ducking already enabled"
EOFDUCKING
    
    if [ "$TARGET_USER" != "$USER" ]; then
        sudo cp /tmp/enable-ducking.sh "$DUCKING_SCRIPT"
        sudo chown "$TARGET_USER:$TARGET_USER" "$DUCKING_SCRIPT"
        sudo chmod +x "$DUCKING_SCRIPT"
    else
        cp /tmp/enable-ducking.sh "$DUCKING_SCRIPT"
        chmod +x "$DUCKING_SCRIPT"
    fi
    rm /tmp/enable-ducking.sh
    
    echo "[+] Ducking script created: $DUCKING_SCRIPT"
    echo "[+] Run as $TARGET_USER to enable: $DUCKING_SCRIPT"
fi

# --- Completion -------------------------------------------------------
echo ""
echo "======================================================================="
echo "✓✓✓ INSTALLATION COMPLETE! ✓✓✓"
echo "======================================================================="
echo ""

if [ "$TARGET_USER" != "$USER" ]; then
    echo "⚠️  IMPORTANT: Talkkonnect is configured to run as user: $TARGET_USER"
    echo "   This allows it to share the PipeWire audio session with your apps"
    echo "   All configuration files are in: $TARGET_HOME/.config/talkkonnect/"
    echo ""
fi

if [ "$NEEDS_RELOGIN" = true ]; then
    echo "⚠️  IMPORTANT: You were added to the 'input' group"
    echo "   You must LOG OUT and LOG BACK IN for keyboard PTT to work!"
    echo "   (Or run: newgrp input)"
    echo ""
fi

echo "BEFORE RUNNING: Edit the configuration file with your Mumble server details"
echo ""
if [ "$TARGET_USER" != "$USER" ]; then
    echo "  1. Edit config file (as $TARGET_USER or with sudo):"
    echo "     sudo nano $CONFIG_DIR/talkkonnect.xml"
else
    echo "  1. Edit config file:"
    echo "     nano $CONFIG_DIR/talkkonnect.xml"
fi
echo ""
echo "  2. Update these settings:"
echo "     - <serverandport>: Your Mumble server address and port"
echo "     - <username>: Your Mumble username"
echo "     - <password>: Your Mumble password (if required)"
echo "     - <channel>: Channel to join on connect"
echo "     - <insecure>: Set to 'true' if server has self-signed cert"
echo ""
echo "  3. Optional - Enable keyboard/USB button PTT (voice activation is enabled by default):"
echo "     - Set <ptt enabled=\"true\">"
echo "     - For USB mini keyboard: Find device with 'sudo evtest'"
echo "     - Set <usbkeyboard enabled=\"true\" device=\"/dev/input/eventX\" keycode=\"KEY_F13\"/>"
echo "     - Tip: Program your USB keyboard to send F13-F24 to avoid conflicts"
echo "     - Set <voiceactivity enabled=\"false\"/>"
if [ "$TARGET_USER" = "$USER" ]; then
    echo "     - Make sure you're in 'input' group: groups | grep input"
fi
echo ""
echo "TESTING:"
if [ "$TARGET_USER" != "$USER" ]; then
    echo "  Test manually as $TARGET_USER:"
    echo "    sudo -u $TARGET_USER /usr/local/bin/talkkonnect -config $CONFIG_DIR/talkkonnect.xml"
else
    echo "  Test manually first:"
    echo "    /usr/local/bin/talkkonnect -config $CONFIG_DIR/talkkonnect.xml"
fi
echo ""
echo "  Once working, start the service:"
echo "    sudo systemctl start talkkonnect"
echo ""
echo "  Check status:"
echo "    sudo systemctl status talkkonnect"
echo ""
echo "  View logs:"
echo "    journalctl -u talkkonnect -f"
echo "    cat $CONFIG_DIR/talkkonnect.log"
echo ""
if [ "$TARGET_USER" != "$USER" ]; then
    echo "AUDIO DUCKING:"
    echo "  To enable audio ducking (lower other apps when transmitting):"
    echo "    sudo -u $TARGET_USER $CONFIG_DIR/enable-ducking.sh"
    echo ""
fi
echo "FILES:"
echo "  Binary:  /usr/local/bin/talkkonnect"
echo "  Config:  $CONFIG_DIR/talkkonnect.xml"
echo "  Service: /etc/systemd/system/talkkonnect.service"
echo "  Source:  ~/talkkonnect"
echo "  Logs:    $CONFIG_DIR/talkkonnect.log"
if [ "$TARGET_USER" != "$USER" ]; then
    echo "  Ducking: $CONFIG_DIR/enable-ducking.sh"
fi
echo ""
echo "TROUBLESHOOTING:"
echo "  - Build log: /tmp/talkkonnect_build.log"
echo "  - Runtime logs: $CONFIG_DIR/talkkonnect.log"
echo "  - System logs: journalctl -u talkkonnect -f"
echo "  - If audio issues: check 'aplay -L' and 'arecord -L'"
echo "  - If 'unable to unmute' error: run 'amixer scontrols' to see controls"
echo "  - If cert errors: set <insecure>true</insecure> in config"
echo "  - For keyboard PTT: ensure you're in 'input' group (groups)"
echo "  - If crash after connect: ensure voicetargets section exists in XML"
echo ""
echo "KNOWN ISSUES:"
echo "  - Voice activation is enabled by default (PTT disabled)"
echo "  - Keyboard PTT requires logout/login after installation"
echo "  - Self-signed certs need <insecure>true</insecure>"
if [ "$TARGET_USER" != "$USER" ]; then
    echo "  - Config files owned by $TARGET_USER - edit with sudo or su"
    echo "  - Audio ducking must be enabled manually (see above)"
fi
echo ""
echo "CHROMEBOOK-SPECIFIC:"
echo "  - If no audio: ensure $TARGET_USER can access /dev/snd devices"
echo "  - Check audio as target user: sudo -u $TARGET_USER aplay -l"
echo "  - PipeWire session: /run/user/$TARGET_UID/pipewire-0"
echo ""
echo "======================================================================="
