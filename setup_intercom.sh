#!/bin/bash
################################################################################
###   UBK Mumble/Talkkonnect Intercom Setup                                 ###
###   Standalone Installation and Management Script                         ###
################################################################################
#
# This script provides a complete push-to-talk (PTT) intercom solution using:
#   - Murmur: The Mumble server (can run on one kiosk)
#   - talkkonnect: A headless Mumble client for push-to-talk communication
#
# Use Cases:
#   1. Server + Client (All-in-one): One kiosk acts as both server and client
#   2. Client Only: Connect to an existing Mumble server
#   3. Server Only: Set up a kiosk as the intercom server
#
# Other kiosks or devices can connect using:
#   - talkkonnect (Linux)
#   - Mumble desktop client (Windows/Mac/Linux)
#   - Mumble mobile app (iOS/Android)
#
################################################################################

VERSION="1.0.0"
KIOSK_USER="${KIOSK_USER:-kiosk}"

################################################################################
### HELPER FUNCTIONS
################################################################################

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "✓ $*"
}

log_warning() {
    echo "⚠ $*"
}

pause() {
    read -r -p "Press Enter to continue..."
}

get_ip_address() {
    hostname -I | awk '{print $1}' || echo "No IP"
}

################################################################################
### STATUS CHECK FUNCTIONS
################################################################################

check_murmur_status() {
    local installed=false
    local running=false

    if systemctl list-unit-files | grep -q "mumble-server.service"; then
        installed=true
        if systemctl is-active --quiet mumble-server; then
            running=true
        fi
    fi

    echo "$installed:$running"
}

check_talkkonnect_status() {
    local installed=false
    local running=false

    if command -v talkkonnect &>/dev/null || [[ -f "$HOME/go/bin/talkkonnect" ]]; then
        installed=true
        if systemctl is-active --quiet talkkonnect; then
            running=true
        fi
    fi

    echo "$installed:$running"
}

################################################################################
### MURMUR SERVER INSTALLATION
################################################################################

install_murmur_server() {
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   INSTALLING MURMUR SERVER"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    echo "[1/5] Installing mumble-server package..."
    sudo apt update
    sudo apt install -y mumble-server

    echo "[2/5] Getting configuration details..."
    read -r -s -p "SuperUser password: " superuser_pass
    echo
    read -r -s -p "Server password (clients need this): " server_pass
    echo
    read -r -p "Welcome text [Welcome to Kiosk Intercom]: " welcome_text
    welcome_text="${welcome_text:-Welcome to Kiosk Intercom}"

    echo "[3/5] Creating configuration..."
    local config_file="/etc/mumble-server.ini"

    # Create config if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        sudo tee "$config_file" > /dev/null <<'MURMURCONF'
# Murmur configuration file

# Database location
database=/var/lib/mumble-server/mumble-server.sqlite

# Network settings
port=64738
host=0.0.0.0

# Logging
logfile=/var/log/mumble-server/mumble-server.log

# Limits
users=10
bandwidth=72000

# Welcome message
welcometext=Welcome

# Server password
serverpassword=

# Allow pings
allowping=true

# Enable HTML
allowhtml=true
MURMURCONF
        log_success "Config file created"
    fi

    # Update configuration
    sudo sed -i "s|^welcometext=.*|welcometext=$welcome_text|" "$config_file"
    sudo sed -i "s|^port=.*|port=64738|" "$config_file"
    sudo sed -i "s|^users=.*|users=10|" "$config_file"
    sudo sed -i "s|^bandwidth=.*|bandwidth=72000|" "$config_file"

    if [[ -n "$server_pass" ]]; then
        sudo sed -i "s|^serverpassword=.*|serverpassword=$server_pass|" "$config_file"
    fi

    echo "[4/5] Setting SuperUser password..."
    # Stop service before setting password
    sudo systemctl stop mumble-server 2>/dev/null || true
    sleep 2

    # Set SuperUser password
    echo "$superuser_pass" | sudo murmurd -ini "$config_file" -supw - 2>/dev/null || {
        log_warning "Could not set SuperUser password via murmurd command"
        echo "You can set it later with: sudo murmurd -ini $config_file -supw YOUR_PASSWORD"
    }

    echo "[5/5] Starting service..."
    sudo systemctl enable mumble-server
    sudo systemctl start mumble-server

    # Configure firewall
    sudo ufw allow 64738/tcp comment 'Mumble/Murmur' 2>/dev/null || true
    sudo ufw allow 64738/udp comment 'Mumble/Murmur' 2>/dev/null || true

    sleep 3

    local server_ip=$(get_ip_address)
    log_success "Murmur server installed"
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Server: $server_ip:64738"
    echo "  SuperUser: SuperUser / $superuser_pass"
    [[ -n "$server_pass" ]] && echo "  Password: $server_pass"
    echo
    echo "Connect with Mumble app:"
    echo "  Server: $server_ip"
    echo "  Port: 64738"
    [[ -n "$server_pass" ]] && echo "  Password: $server_pass"
    echo "═══════════════════════════════════════════════════════════════"

    pause
}

################################################################################
### TALKKONNECT CLIENT INSTALLATION
################################################################################

install_talkkonnect_with_config() {
    local server_addr="$1"
    local server_port="$2"
    local tk_user="$3"
    local tk_pass="$4"
    local tk_channel="$5"

    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   INSTALLING TALKKONNECT CLIENT"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    echo "[1/4] Installing Go..."
    if ! command -v go &>/dev/null; then
        wget -q https://golang.org/dl/go1.23.4.linux-amd64.tar.gz
        sudo tar -C /usr/local -xzf go1.23.4.linux-amd64.tar.gz
        rm go1.23.4.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh
        log_success "Go installed"
    else
        log_success "Go already installed"
    fi

    echo "[2/4] Installing audio dependencies..."
    sudo apt install -y libopenal-dev libopus-dev libopus0 libopusfile-dev alsa-utils portaudio19-dev git build-essential pkg-config

    echo "[3/4] Cloning and building talkkonnect..."

    echo "Building (this takes 5-10 minutes)..."

    # Build as kiosk user with proper environment (using their home directory to avoid permission issues)
    sudo -u "$KIOSK_USER" bash -c "
        export PATH=/usr/local/go/bin:\$PATH
        export HOME=/home/$KIOSK_USER
        export GOPATH=/home/$KIOSK_USER/go
        export CGO_ENABLED=1

        mkdir -p /home/$KIOSK_USER/go/bin

        # Clone to kiosk user's home directory (avoids /tmp permission issues)
        cd /home/$KIOSK_USER || exit 1

        if [[ -d talkkonnect ]]; then
            echo 'Removing existing talkkonnect directory...'
            rm -rf talkkonnect
        fi

        git clone https://github.com/talkkonnect/talkkonnect.git
        cd talkkonnect || exit 1

        echo 'Creating vendored dependencies...'
        go mod vendor

        # Apply critical x86_64 Opus patch
        echo 'Applying x86_64 Opus compatibility patch...'
        if [[ -f vendor/github.com/talkkonnect/gopus/opus_nonshared.go ]]; then
            cp vendor/github.com/talkkonnect/gopus/opus_nonshared.go \
               vendor/github.com/talkkonnect/gopus/opus_nonshared.go.backup

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
import \"C\"

import (
	\"errors\"
	\"unsafe\"
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
	ErrBadArgument   = errors.New(\"bad argument\")
	ErrSmallBuffer   = errors.New(\"buffer is too small\")
	ErrInternal      = errors.New(\"internal error\")
	ErrInvalidPacket = errors.New(\"invalid packet\")
	ErrUnimplemented = errors.New(\"unimplemented\")
	ErrInvalidState  = errors.New(\"invalid state\")
	ErrAllocFail     = errors.New(\"allocation failed\")
	ErrUnknown       = errors.New(\"unknown error\")
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
            echo 'Opus patch applied'
        else
            echo 'Warning: gopus not found in vendor directory'
        fi

        # Set CGO flags for Opus
        export CGO_CFLAGS=\"\$(pkg-config --cflags opus)\"
        export CGO_LDFLAGS=\"\$(pkg-config --libs opus) -lm\"

        # Build in the cmd/talkkonnect directory with vendored dependencies
        cd cmd/talkkonnect || exit 1

        echo 'Compiling with vendored dependencies...'
        go build -mod=vendor -v -o /home/$KIOSK_USER/talkkonnect-binary . 2>&1 | tail -20

        if [[ -f /home/$KIOSK_USER/talkkonnect-binary ]]; then
            chmod +x /home/$KIOSK_USER/talkkonnect-binary
            echo 'Build successful'
            exit 0
        else
            echo 'Build failed - binary not created'
            exit 1
        fi
    "

    local build_result=$?

    if [[ $build_result -ne 0 ]]; then
        log_error "Build failed"
        echo
        echo "Troubleshooting:"
        echo "  1. Check Go version: go version"
        echo "  2. Ensure build tools: sudo apt install build-essential"
        echo "  3. Check logs above for specific errors"
        pause
        return 1
    fi

    # Verify and install binary
    if [[ ! -x "/home/$KIOSK_USER/talkkonnect-binary" ]]; then
        log_error "Binary not executable after build"
        pause
        return 1
    fi

    echo "Installing binary..."
    sudo cp /home/$KIOSK_USER/talkkonnect-binary /home/$KIOSK_USER/go/bin/talkkonnect
    sudo chmod +x /home/$KIOSK_USER/go/bin/talkkonnect
    sudo chown "$KIOSK_USER:$KIOSK_USER" /home/$KIOSK_USER/go/bin/talkkonnect
    rm -f /home/$KIOSK_USER/talkkonnect-binary

    log_success "talkkonnect built successfully"

    echo "[4/4] Creating configuration..."

    # Create config directory for logs
    sudo -u "$KIOSK_USER" mkdir -p /home/$KIOSK_USER/.config/talkkonnect

    sudo -u "$KIOSK_USER" tee /home/$KIOSK_USER/talkkonnect.xml > /dev/null <<TKXML
<?xml version="1.0" encoding="UTF-8"?>
<document type="talkkonnect/xml">
  <global>
    <software>
      <settings outputdevice="default"
                logfilenameandpath="/home/$KIOSK_USER/.config/talkkonnect/talkkonnect.log"
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
      <serverandport>$server_addr:$server_port</serverandport>
      <username>$tk_user</username>
      <password>$tk_pass</password>
      <insecure>true</insecure>
      <register>false</register>
      <certificate></certificate>
      <channel>$tk_channel</channel>
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
TKXML

    # Create systemd service
    sudo tee /etc/systemd/system/talkkonnect.service > /dev/null <<EOF
[Unit]
Description=talkkonnect Mumble Client
After=network.target sound.target pipewire.service
Wants=pipewire.service

[Service]
Type=simple
User=$KIOSK_USER
Environment="PATH=/usr/local/go/bin:/usr/bin:/bin"
Environment="HOME=/home/$KIOSK_USER"
Environment="GOPATH=/home/$KIOSK_USER/go"
WorkingDirectory=/home/$KIOSK_USER
ExecStartPre=/bin/sleep 10
ExecStart=/home/$KIOSK_USER/go/bin/talkkonnect -config /home/$KIOSK_USER/talkkonnect.xml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable talkkonnect
    sudo systemctl start talkkonnect

    sleep 3

    log_success "talkkonnect installed"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Server: $server_addr:$server_port"
    echo "  PTT Key: Spacebar"
    echo "═══════════════════════════════════════════════════════════════"

    # Show status
    echo
    if systemctl is-active --quiet talkkonnect; then
        log_success "Service started successfully"
    else
        log_warning "Service may have issues - check logs:"
        echo "  sudo journalctl -u talkkonnect -n 50"
    fi

    pause
}

install_talkkonnect_only() {
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   TALKKONNECT - CONNECT TO EXISTING SERVER"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    echo "Enter Murmur/Mumble server details:"
    read -r -p "Server address (IP or domain): " server_addr
    read -r -p "Port [64738]: " server_port
    server_port="${server_port:-64738}"
    read -r -p "Username: " tk_user
    read -r -s -p "Password: " tk_pass
    echo
    read -r -p "Channel [Root]: " tk_channel
    tk_channel="${tk_channel:-Root}"

    install_talkkonnect_with_config "$server_addr" "$server_port" "$tk_user" "$tk_pass" "$tk_channel"
}

install_murmur_and_talkkonnect() {
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   ALL-IN-ONE: SERVER + CLIENT"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    echo "Installing Murmur server..."
    install_murmur_server

    echo
    echo "Now installing talkkonnect client..."
    echo "Configuring to connect to local server..."

    # Auto-configure for local server
    AUTO_SERVER="127.0.0.1"
    AUTO_PORT="64738"
    read -r -p "Username for talkkonnect [kiosk]: " tk_user
    tk_user="${tk_user:-kiosk}"
    read -r -s -p "Server password: " tk_pass
    echo

    install_talkkonnect_with_config "$AUTO_SERVER" "$AUTO_PORT" "$tk_user" "$tk_pass" "Root"
}

################################################################################
### SERVICE MANAGEMENT
################################################################################

toggle_murmur_service() {
    echo
    if systemctl is-active --quiet mumble-server; then
        echo "Stopping Murmur server..."
        sudo systemctl stop mumble-server
        log_success "Murmur stopped"
    else
        echo "Starting Murmur server..."
        sudo systemctl start mumble-server
        sleep 2
        if systemctl is-active --quiet mumble-server; then
            log_success "Murmur started"
        else
            log_error "Failed to start - check logs: sudo journalctl -u mumble-server"
        fi
    fi
    pause
}

toggle_talkkonnect_service() {
    echo
    if systemctl is-active --quiet talkkonnect; then
        echo "Stopping talkkonnect..."
        sudo systemctl stop talkkonnect
        log_success "talkkonnect stopped"
    else
        echo "Starting talkkonnect..."
        sudo systemctl start talkkonnect
        sleep 2
        if systemctl is-active --quiet talkkonnect; then
            log_success "talkkonnect started"
        else
            log_error "Failed to start - check logs: sudo journalctl -u talkkonnect"
        fi
    fi
    pause
}

################################################################################
### RECONFIGURATION
################################################################################

reconfigure_murmur() {
    echo
    echo "Reconfigure Murmur Server:"
    echo "  1. Change welcome text"
    echo "  2. Change server password"
    echo "  3. Change SuperUser password"
    echo "  4. Change port"
    echo "  0. Cancel"
    read -r -p "Choose: " reconfig_choice

    local config_file="/etc/mumble-server.ini"

    case "$reconfig_choice" in
        1)
            read -r -p "New welcome text: " new_welcome
            sudo sed -i "s|^welcometext=.*|welcometext=$new_welcome|" "$config_file"
            sudo systemctl restart mumble-server
            log_success "Welcome text updated"
            ;;
        2)
            read -r -s -p "New server password (blank=none): " new_pass
            echo
            sudo sed -i "s|^serverpassword=.*|serverpassword=$new_pass|" "$config_file"
            sudo systemctl restart mumble-server
            log_success "Server password updated"
            ;;
        3)
            read -r -s -p "New SuperUser password: " su_pass
            echo
            sudo systemctl stop mumble-server
            echo "$su_pass" | sudo murmurd -ini "$config_file" -supw - 2>/dev/null
            sudo systemctl start mumble-server
            log_success "SuperUser password updated"
            ;;
        4)
            read -r -p "New port [64738]: " new_port
            new_port="${new_port:-64738}"
            sudo sed -i "s|^port=.*|port=$new_port|" "$config_file"
            sudo systemctl restart mumble-server
            log_success "Port updated to $new_port"
            ;;
    esac
    pause
}

reconfigure_talkkonnect() {
    echo
    echo "Reconfigure talkkonnect:"
    echo "  1. Change server"
    echo "  2. Change credentials"
    echo "  3. Change channel"
    echo "  0. Cancel"
    read -r -p "Choose: " reconfig_choice

    case "$reconfig_choice" in
        1)
            read -r -p "Server address: " new_server
            read -r -p "Port [64738]: " new_port
            new_port="${new_port:-64738}"
            sudo -u "$KIOSK_USER" sed -i "s|<server>.*</server>|<server>$new_server</server>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo -u "$KIOSK_USER" sed -i "s|<port>.*</port>|<port>$new_port</port>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo systemctl restart talkkonnect
            log_success "Server updated"
            ;;
        2)
            read -r -p "Username: " new_user
            read -r -s -p "Password: " new_pass
            echo
            sudo -u "$KIOSK_USER" sed -i "s|<username>.*</username>|<username>$new_user</username>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo -u "$KIOSK_USER" sed -i "s|<password>.*</password>|<password>$new_pass</password>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo systemctl restart talkkonnect
            log_success "Credentials updated"
            ;;
        3)
            read -r -p "Channel: " new_channel
            sudo -u "$KIOSK_USER" sed -i "s|<channel>.*</channel>|<channel>$new_channel</channel>|" /home/$KIOSK_USER/talkkonnect.xml
            sudo systemctl restart talkkonnect
            log_success "Channel updated"
            ;;
    esac
    pause
}

################################################################################
### LOGS AND DIAGNOSTICS
################################################################################

view_talkkonnect_logs() {
    echo
    echo "Recent talkkonnect logs:"
    echo "═══════════════════════════════════════════════════════════════"
    sudo journalctl -u talkkonnect -n 50 --no-pager
    echo
    pause
}

view_murmur_logs() {
    echo
    echo "Recent Murmur server logs:"
    echo "═══════════════════════════════════════════════════════════════"
    sudo journalctl -u mumble-server -n 50 --no-pager
    echo
    pause
}

################################################################################
### UNINSTALLATION
################################################################################

uninstall_murmur() {
    echo
    read -r -p "Uninstall Murmur server? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && return

    echo "Uninstalling..."
    sudo systemctl stop mumble-server 2>/dev/null || true
    sudo systemctl disable mumble-server 2>/dev/null || true
    sudo apt remove -y mumble-server 2>/dev/null || true

    read -r -p "Remove configuration and database? (y/n): " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        sudo rm -rf /var/lib/mumble-server
        sudo rm -f /etc/mumble-server.ini
        log_success "Murmur and data removed"
    else
        log_success "Murmur removed (data preserved)"
    fi

    pause
}

uninstall_talkkonnect() {
    echo
    read -r -p "Uninstall talkkonnect? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && return

    echo "Uninstalling..."
    sudo systemctl stop talkkonnect 2>/dev/null || true
    sudo systemctl disable talkkonnect 2>/dev/null || true
    sudo rm -f /etc/systemd/system/talkkonnect.service
    sudo rm -f /home/$KIOSK_USER/talkkonnect.xml
    sudo rm -f /home/$KIOSK_USER/go/bin/talkkonnect

    sudo systemctl daemon-reload

    log_success "talkkonnect uninstalled"
    pause
}

################################################################################
### MAIN MENU
################################################################################

show_status() {
    local murmur_status=$(check_murmur_status)
    local murmur_installed=$(echo "$murmur_status" | cut -d: -f1)
    local murmur_running=$(echo "$murmur_status" | cut -d: -f2)

    local tk_status=$(check_talkkonnect_status)
    local tk_installed=$(echo "$tk_status" | cut -d: -f1)
    local tk_running=$(echo "$tk_status" | cut -d: -f2)

    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   INTERCOM STATUS"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    # Murmur status
    if [[ "$murmur_installed" == "true" ]]; then
        echo "Murmur Server: ✓ Installed"
        if [[ "$murmur_running" == "true" ]]; then
            echo "  Status: Running"
            local server_ip=$(get_ip_address)
            echo "  Address: $server_ip:64738"
        else
            echo "  Status: Stopped"
        fi
        echo
    else
        echo "Murmur Server: Not installed"
        echo
    fi

    # talkkonnect status
    if [[ "$tk_installed" == "true" ]]; then
        echo "talkkonnect Client: ✓ Installed"
        if [[ "$tk_running" == "true" ]]; then
            echo "  Status: Running"
            if [[ -f /home/$KIOSK_USER/talkkonnect.xml ]]; then
                local server=$(grep "serveraddress" /home/$KIOSK_USER/talkkonnect.xml 2>/dev/null | sed 's/.*<server>\(.*\)<\/server>/\1/' || echo "Unknown")
                echo "  Server: $server"
            fi
        else
            echo "  Status: Stopped"
        fi
        echo
    else
        echo "talkkonnect Client: Not installed"
        echo
    fi
}

main_menu() {
    while true; do
        clear
        echo "═══════════════════════════════════════════════════════════════"
        echo "   UBK INTERCOM SETUP v${VERSION}"
        echo "   Mumble/Talkkonnect Push-to-Talk System"
        echo "═══════════════════════════════════════════════════════════════"

        show_status

        local murmur_status=$(check_murmur_status)
        local murmur_installed=$(echo "$murmur_status" | cut -d: -f1)
        local murmur_running=$(echo "$murmur_status" | cut -d: -f2)

        local tk_status=$(check_talkkonnect_status)
        local tk_installed=$(echo "$tk_status" | cut -d: -f1)
        local tk_running=$(echo "$tk_status" | cut -d: -f2)

        echo "═══════════════════════════════════════════════════════════════"
        echo "   INSTALLATION OPTIONS"
        echo "═══════════════════════════════════════════════════════════════"

        local menu_num=1

        # Installation options (shown when nothing installed)
        if [[ "$murmur_installed" == "false" && "$tk_installed" == "false" ]]; then
            echo "  $menu_num. Install All-in-One (Server + Client)"
            local opt_all_in_one=$menu_num
            ((menu_num++))
            echo "  $menu_num. Install Murmur Server Only"
            local opt_server_only=$menu_num
            ((menu_num++))
            echo "  $menu_num. Install talkkonnect Client Only"
            local opt_client_only=$menu_num
            ((menu_num++))
        else
            # Murmur management options
            if [[ "$murmur_installed" == "true" ]]; then
                echo
                echo "Murmur Server:"
                if [[ "$murmur_running" == "true" ]]; then
                    echo "  $menu_num. Stop Murmur"
                else
                    echo "  $menu_num. Start Murmur"
                fi
                local opt_murmur_toggle=$menu_num
                ((menu_num++))

                echo "  $menu_num. Reconfigure Murmur"
                local opt_murmur_reconfig=$menu_num
                ((menu_num++))

                echo "  $menu_num. View Murmur Logs"
                local opt_murmur_logs=$menu_num
                ((menu_num++))

                echo "  $menu_num. Uninstall Murmur"
                local opt_murmur_uninstall=$menu_num
                ((menu_num++))
            else
                echo
                echo "  $menu_num. Install Murmur Server"
                local opt_install_murmur=$menu_num
                ((menu_num++))
            fi

            # talkkonnect management options
            if [[ "$tk_installed" == "true" ]]; then
                echo
                echo "talkkonnect Client:"
                if [[ "$tk_running" == "true" ]]; then
                    echo "  $menu_num. Stop talkkonnect"
                else
                    echo "  $menu_num. Start talkkonnect"
                fi
                local opt_tk_toggle=$menu_num
                ((menu_num++))

                echo "  $menu_num. Reconfigure talkkonnect"
                local opt_tk_reconfig=$menu_num
                ((menu_num++))

                echo "  $menu_num. View talkkonnect Logs"
                local opt_tk_logs=$menu_num
                ((menu_num++))

                echo "  $menu_num. Uninstall talkkonnect"
                local opt_tk_uninstall=$menu_num
                ((menu_num++))
            else
                echo
                echo "  $menu_num. Install talkkonnect Client"
                local opt_install_tk=$menu_num
                ((menu_num++))
            fi
        fi

        echo
        echo "═══════════════════════════════════════════════════════════════"
        echo "  0. Exit"
        echo "═══════════════════════════════════════════════════════════════"
        echo
        read -r -p "Choose [0-$((menu_num-1))]: " choice

        # Handle menu selection
        case "$choice" in
            0)
                echo "Exiting..."
                exit 0
                ;;
            ${opt_all_in_one:-})
                install_murmur_and_talkkonnect
                ;;
            ${opt_server_only:-})
                install_murmur_server
                ;;
            ${opt_client_only:-})
                install_talkkonnect_only
                ;;
            ${opt_install_murmur:-})
                install_murmur_server
                ;;
            ${opt_install_tk:-})
                install_talkkonnect_only
                ;;
            ${opt_murmur_toggle:-})
                toggle_murmur_service
                ;;
            ${opt_murmur_reconfig:-})
                reconfigure_murmur
                ;;
            ${opt_murmur_logs:-})
                view_murmur_logs
                ;;
            ${opt_murmur_uninstall:-})
                uninstall_murmur
                ;;
            ${opt_tk_toggle:-})
                toggle_talkkonnect_service
                ;;
            ${opt_tk_reconfig:-})
                reconfigure_talkkonnect
                ;;
            ${opt_tk_logs:-})
                view_talkkonnect_logs
                ;;
            ${opt_tk_uninstall:-})
                uninstall_talkkonnect
                ;;
            *)
                echo "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

################################################################################
### ENTRY POINT
################################################################################

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root"
    echo "Please run as: ./setup_intercom.sh"
    exit 1
fi

# Check if kiosk user exists
if ! id "$KIOSK_USER" &>/dev/null; then
    log_warning "User '$KIOSK_USER' does not exist"
    read -r -p "Enter the username to use for installation: " KIOSK_USER

    if ! id "$KIOSK_USER" &>/dev/null; then
        log_error "User '$KIOSK_USER' not found"
        exit 1
    fi
fi

# Run main menu
main_menu
