#!/bin/bash

# Interactive Kiosk Mumble Client Installer
# With systemd service and fixed audio

set -e

echo "========================================"
echo "Kiosk Mumble Client Installer"
echo "Interactive Setup with Systemd Service"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

TARGET_USER="${1:-kiosk}"
USER_HOME=$(eval echo "~$TARGET_USER")

echo ""
print_info "Target user: $TARGET_USER"
print_info "Home directory: $USER_HOME"
echo ""

# Check if user exists
if ! id "$TARGET_USER" &>/dev/null; then
    print_error "User $TARGET_USER does not exist"
    exit 1
fi

# Interactive configuration
echo "========================================="
echo "Mumble Server Configuration"
echo "========================================="
echo ""

read -p "Mumble server address [mumble.example.org]: " MUMBLE_SERVER
MUMBLE_SERVER=${MUMBLE_SERVER:-mumble.example.org}

read -p "Port [64738]: " MUMBLE_PORT
MUMBLE_PORT=${MUMBLE_PORT:-64738}

read -p "Username [$TARGET_USER]: " MUMBLE_USERNAME
MUMBLE_USERNAME=${MUMBLE_USERNAME:-$TARGET_USER}

read -sp "Password (leave empty if none): " MUMBLE_PASSWORD
echo ""

read -p "Channel to join (leave empty for root): " MUMBLE_CHANNEL

read -p "Skip SSL verification? (y/N): " MUMBLE_INSECURE
MUMBLE_INSECURE=${MUMBLE_INSECURE:-n}

echo ""
echo "Configuration Summary:"
echo "----------------------"
echo "Server: $MUMBLE_SERVER:$MUMBLE_PORT"
echo "Username: $MUMBLE_USERNAME"
echo "Password: $([ -n "$MUMBLE_PASSWORD" ] && echo '(set)' || echo '(none)')"
echo "Channel: ${MUMBLE_CHANNEL:-(root)}"
echo "Skip SSL: $MUMBLE_INSECURE"
echo ""
read -p "Continue with installation? (Y/n): " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

# Check prerequisites
print_info "Checking prerequisites..."

if ! command -v go &> /dev/null; then
    print_warning "Go not installed, installing..."
    sudo apt update
    sudo apt install -y golang-go
fi
print_success "Go installed: $(go version)"

# Install system dependencies
print_info "Installing system dependencies..."
sudo apt install -y \
    libopus-dev \
    portaudio19-dev \
    pkg-config \
    build-essential \
    git \
    pulseaudio-utils

print_success "System dependencies installed"

# Create workspace
WORK_DIR="$USER_HOME/kiosk-mumble"
print_info "Creating workspace at $WORK_DIR..."
sudo -u "$TARGET_USER" mkdir -p "$WORK_DIR"

# Save the Go source code with FIXED audio callback
print_info "Creating source files..."
sudo -u "$TARGET_USER" bash << 'EOF'
cat > "$HOME/kiosk-mumble/main.go" << 'GOSRC'
package main

import (
	"crypto/tls"
	"encoding/binary"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"github.com/gordonklaus/portaudio"
	"layeh.com/gumble/gumble"
	"layeh.com/gumble/gumbleutil"
	_ "layeh.com/gumble/opus"
)

const (
	AudioSampleRate = 48000
	AudioFrameSize  = 960
	AudioChannels   = 1
)

type MumbleClient struct {
	client        *gumble.Client
	config        *gumble.Config
	stream        *portaudio.Stream
	transmitting  bool
	targetChannel string
	audioOut      chan<- gumble.AudioBuffer
	pttDevice     string
	pttKeyCode    int
}

func main() {
	server := flag.String("server", "localhost:64738", "Mumble server (host:port)")
	username := flag.String("username", "kiosk-client", "Username")
	password := flag.String("password", "", "Server password")
	channel := flag.String("channel", "", "Channel to join")
	insecure := flag.Bool("insecure", false, "Skip TLS verification")
	vad := flag.Bool("vad", false, "Voice activity detection")
	pttKey := flag.String("ptt-key", "", "PTT key: 'space', 'mute', 'f13', etc")
	pttDevice := flag.String("ptt-device", "", "PTT input device")
	listDevices := flag.Bool("list-devices", false, "List input devices and exit")

	flag.Parse()

	if *listDevices {
		listInputDevices()
		return
	}

	fmt.Println("╔════════════════════════════════╗")
	fmt.Println("║  Kiosk Mumble Client v1.0     ║")
	fmt.Println("╚════════════════════════════════╝")
	fmt.Println()

	if err := portaudio.Initialize(); err != nil {
		log.Fatalf("PortAudio init failed: %v", err)
	}
	defer portaudio.Terminate()

	config := gumble.NewConfig()
	config.Username = *username
	config.Password = *password

	tlsConfig := &tls.Config{InsecureSkipVerify: *insecure}

	mc := &MumbleClient{
		config:        config,
		transmitting:  *vad,
		targetChannel: *channel,
		pttDevice:     *pttDevice,
	}

	if *pttKey != "" {
		mc.pttKeyCode = parsePTTKey(*pttKey)
		if mc.pttDevice == "" {
			mc.pttDevice = findBestInputDevice()
		}
	}

	config.Attach(gumbleutil.Listener{
		Connect:     mc.onConnect,
		Disconnect:  mc.onDisconnect,
		UserChange:  mc.onUserChange,
		TextMessage: mc.onTextMessage,
	})

	fmt.Printf("Connecting to %s as '%s'...\n", *server, *username)
	if *password != "" {
		fmt.Println("Using password authentication")
	}

	client, err := gumble.DialWithDialer(new(net.Dialer), *server, config, tlsConfig)
	if err != nil {
		log.Fatalf("Connection failed: %v", err)
	}
	mc.client = client
	defer client.Disconnect()

	fmt.Println("✓ Connected!")

	if err := mc.setupAudio(); err != nil {
		log.Fatalf("Audio setup failed: %v", err)
	}
	defer mc.stream.Close()

	if err := mc.stream.Start(); err != nil {
		log.Fatalf("Audio start failed: %v", err)
	}
	defer mc.stream.Stop()

	fmt.Println()
	fmt.Println("Controls:")
	if *vad {
		fmt.Println("  Mode: Voice Activity Detection (always transmitting)")
	} else if *pttKey != "" {
		fmt.Printf("  Mode: Push-to-Talk (key: %s)\n", *pttKey)
		if mc.pttDevice != "" {
			fmt.Printf("  Device: %s\n", mc.pttDevice)
		}
	} else {
		fmt.Println("  Mode: Manual (no transmission)")
	}
	fmt.Println("  Ctrl+C: Quit")
	fmt.Println()

	if *pttKey != "" && mc.pttDevice != "" {
		go mc.monitorPTT()
	}

	if mc.targetChannel != "" {
		time.Sleep(500 * time.Millisecond)
		mc.joinChannel(mc.targetChannel)
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	fmt.Println("\nDisconnecting...")
}

func (mc *MumbleClient) setupAudio() error {
	mc.audioOut = mc.client.AudioOutgoing()

	h, err := portaudio.DefaultHostApi()
	if err != nil {
		return fmt.Errorf("failed to get default host API: %w", err)
	}

	p := portaudio.LowLatencyParameters(h.DefaultInputDevice, nil)
	p.Input.Channels = AudioChannels

	fmt.Printf("Audio: Using device '%s'\n", h.DefaultInputDevice.Name)

	stream, err := portaudio.OpenStream(p, func(in, out []int16) {
		if !mc.transmitting || mc.audioOut == nil {
			return
		}
		pcm := make([]int16, len(in))
		copy(pcm, in)
		select {
		case mc.audioOut <- pcm:
		default:
		}
	})
	if err != nil {
		return fmt.Errorf("failed to open audio stream: %w", err)
	}

	mc.stream = stream
	return nil
}

func (mc *MumbleClient) monitorPTT() {
	file, err := os.Open(mc.pttDevice)
	if err != nil {
		fmt.Printf("⚠ Failed to open PTT device %s: %v\n", mc.pttDevice, err)
		fmt.Println("⚠ PTT will not work. Try running with sudo or add user to 'input' group:")
		fmt.Printf("   sudo usermod -a -G input %s\n", os.Getenv("USER"))
		return
	}
	defer file.Close()

	fmt.Printf("✓ PTT monitoring started on %s\n", mc.pttDevice)

	type inputEvent struct {
		Time  syscall.Timeval
		Type  uint16
		Code  uint16
		Value int32
	}

	for {
		var event inputEvent
		err := binary.Read(file, binary.LittleEndian, &event)
		if err != nil {
			fmt.Printf("⚠ PTT monitoring error: %v\n", err)
			return
		}

		if event.Type == 1 && int(event.Code) == mc.pttKeyCode {
			if event.Value == 1 {
				mc.transmitting = true
				fmt.Println("🎤 Transmitting...")
			} else if event.Value == 0 {
				mc.transmitting = false
				fmt.Println("🔇 Not transmitting")
			}
		}
	}
}

func parsePTTKey(key string) int {
	keyMap := map[string]int{
		"space":        57,
		"mute":         113,
		"volumeup":     115,
		"volumedown":   114,
		"playpause":    164,
		"previoussong": 165,
		"nextsong":     163,
		"f13":          183,
		"f14":          184,
		"f15":          185,
		"f16":          186,
		"f17":          187,
		"f18":          188,
		"f19":          189,
		"f20":          190,
		"leftctrl":     29,
		"rightctrl":    97,
		"leftalt":      56,
		"rightalt":     100,
		"capslock":     58,
		"numlock":      69,
		"scrolllock":   70,
	}

	key = strings.ToLower(strings.TrimSpace(key))
	if code, ok := keyMap[key]; ok {
		return code
	}

	var code int
	if _, err := fmt.Sscanf(key, "%d", &code); err == nil {
		return code
	}

	fmt.Printf("⚠ Unknown key '%s', using Space\n", key)
	return 57
}

func findBestInputDevice() string {
	devices, err := filepath.Glob("/dev/input/event*")
	if err != nil || len(devices) == 0 {
		return ""
	}

	for _, dev := range devices {
		name := getDeviceName(dev)
		if strings.Contains(strings.ToLower(name), "keyboard") {
			return dev
		}
	}

	if len(devices) > 0 {
		return devices[0]
	}
	return ""
}

func getDeviceName(devicePath string) string {
	sysPath := "/sys/class/input/" + filepath.Base(devicePath) + "/device/name"
	data, err := os.ReadFile(sysPath)
	if err == nil {
		return strings.TrimSpace(string(data))
	}
	return devicePath
}

func listInputDevices() {
	fmt.Println("Available Input Devices:")
	fmt.Println("========================")
	fmt.Println()

	devices, err := filepath.Glob("/dev/input/event*")
	if err != nil {
		fmt.Println("Error listing devices:", err)
		return
	}

	if len(devices) == 0 {
		fmt.Println("No input devices found")
		fmt.Println("Note: You may need to run with sudo")
		return
	}

	re := regexp.MustCompile(`event(\d+)`)
	for _, dev := range devices {
		name := getDeviceName(dev)
		match := re.FindStringSubmatch(dev)
		eventNum := ""
		if len(match) > 1 {
			eventNum = match[1]
		}

		fmt.Printf("  %s\n", dev)
		fmt.Printf("    Name: %s\n", name)
		if eventNum != "" {
			fmt.Printf("    Event: %s\n", eventNum)
		}
		fmt.Println()
	}

	fmt.Println("Common PTT Keys:")
	fmt.Println("  -ptt-key mute       # Mute media key")
	fmt.Println("  -ptt-key space      # Spacebar")
	fmt.Println("  -ptt-key f13        # F13")
	fmt.Println("  -ptt-key capslock   # Caps Lock")
	fmt.Println()
}

func (mc *MumbleClient) onConnect(e *gumble.ConnectEvent) {
	fmt.Println("✓ Connected to server")
	fmt.Printf("  Server: %s\n", e.Client.Conn.RemoteAddr())
	fmt.Printf("  Users: %d online\n", len(e.Client.Users))
	fmt.Printf("  Channels: %d\n", len(e.Client.Channels))
}

func (mc *MumbleClient) onDisconnect(e *gumble.DisconnectEvent) {
	fmt.Println("✗ Disconnected from server")
	if e.String != "" {
		fmt.Printf("  Reason: %s\n", e.String)
	}
}

func (mc *MumbleClient) onUserChange(e *gumble.UserChangeEvent) {
	if e.Type.Has(gumble.UserChangeConnected) {
		fmt.Printf("→ %s joined\n", e.User.Name)
	}
	if e.Type.Has(gumble.UserChangeDisconnected) {
		fmt.Printf("← %s left\n", e.User.Name)
	}
	if e.Type.Has(gumble.UserChangeChannel) {
		if e.User.Channel != nil {
			fmt.Printf("↔ %s moved to %s\n", e.User.Name, e.User.Channel.Name)
		}
	}
}

func (mc *MumbleClient) onTextMessage(e *gumble.TextMessageEvent) {
	if e.Sender != nil {
		fmt.Printf("💬 %s: %s\n", e.Sender.Name, e.Message)
	} else {
		fmt.Printf("💬 Server: %s\n", e.Message)
	}
}

func (mc *MumbleClient) joinChannel(channelPath string) {
	if mc.client == nil || mc.client.Self == nil {
		fmt.Printf("⚠ Client not ready yet, retrying...\n")
		time.Sleep(1 * time.Second)
		if mc.client == nil || mc.client.Self == nil {
			fmt.Printf("⚠ Cannot join channel: client not initialized\n")
			return
		}
	}

	parts := strings.Split(channelPath, "/")

	var targetChannel *gumble.Channel
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		found := false
		for _, ch := range mc.client.Channels {
			if ch.Name == part {
				if targetChannel == nil {
					if ch.Parent == nil || ch.Parent.Parent == nil {
						targetChannel = ch
						found = true
						break
					}
				} else {
					if ch.Parent != nil && ch.Parent.ID == targetChannel.ID {
						targetChannel = ch
						found = true
						break
					}
				}
			}
		}

		if !found {
			fmt.Printf("⚠ Channel not found: %s\n", part)
			fmt.Println("Available channels:")
			mc.listChannels()
			return
		}
	}

	if targetChannel != nil {
		mc.client.Self.Move(targetChannel)
		fmt.Printf("✓ Joined channel: %s\n", channelPath)
	}
}

func (mc *MumbleClient) listChannels() {
	for _, ch := range mc.client.Channels {
		indent := strings.Repeat("  ", getChannelDepth(ch))
		fmt.Printf("%s- %s\n", indent, ch.Name)
	}
}

func getChannelDepth(ch *gumble.Channel) int {
	depth := 0
	current := ch
	for current.Parent != nil {
		depth++
		current = current.Parent
	}
	return depth
}
GOSRC
EOF

print_success "Source code created"

# Build
print_info "Building client (this may take ~45 minutes)..."
sudo -u "$TARGET_USER" bash << 'EOF'
cd "$HOME/kiosk-mumble"

go mod init kiosk-mumble 2>/dev/null || true

echo "Downloading dependencies..."
go get layeh.com/gumble/gumble@latest
go get layeh.com/gumble/gumbleutil@latest
go get layeh.com/gumble/opus@latest
go get github.com/gordonklaus/portaudio@latest

go mod tidy

echo "Compiling..."
CGO_ENABLED=1 go build -o kiosk-mumble main.go

if [ -f kiosk-mumble ]; then
    echo "✓ Build successful!"
    mkdir -p "$HOME/bin"
    cp kiosk-mumble "$HOME/bin/"
    chmod +x "$HOME/bin/kiosk-mumble"
    echo "✓ Installed to $HOME/bin/kiosk-mumble"
else
    echo "✗ Build failed"
    exit 1
fi
EOF

BUILD_RESULT=$?

if [ $BUILD_RESULT -ne 0 ]; then
    print_error "Build failed!"
    exit 1
fi

print_success "Build complete!"

# Configure permissions
print_info "Configuring permissions..."

if ! groups "$TARGET_USER" | grep -q '\binput\b'; then
    sudo usermod -a -G input "$TARGET_USER"
    print_success "Added to input group"
else
    print_success "Already in input group"
fi

if ! groups "$TARGET_USER" | grep -q '\baudio\b'; then
    sudo usermod -a -G audio "$TARGET_USER"
    print_success "Added to audio group"
else
    print_success "Already in audio group"
fi

# Create systemd service
print_info "Creating systemd service..."

INSECURE_FLAG=""
if [[ "$MUMBLE_INSECURE" =~ ^[Yy]$ ]]; then
    INSECURE_FLAG="-insecure"
fi

PASSWORD_FLAG=""
if [ -n "$MUMBLE_PASSWORD" ]; then
    PASSWORD_FLAG="-password \"$MUMBLE_PASSWORD\""
fi

CHANNEL_FLAG=""
if [ -n "$MUMBLE_CHANNEL" ]; then
    CHANNEL_FLAG="-channel \"$MUMBLE_CHANNEL\""
fi

sudo tee /etc/systemd/system/kiosk-mumble.service > /dev/null << SERVICEEOF
[Unit]
Description=Kiosk Mumble Client
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_USER
Environment="XDG_RUNTIME_DIR=/run/user/$(id -u $TARGET_USER)"
Environment="PULSE_SERVER=/run/user/$(id -u $TARGET_USER)/pulse/native"
ExecStart=$USER_HOME/bin/kiosk-mumble -server $MUMBLE_SERVER:$MUMBLE_PORT -username $MUMBLE_USERNAME $PASSWORD_FLAG $CHANNEL_FLAG $INSECURE_FLAG -vad
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl daemon-reload
print_success "Systemd service created"

echo ""
echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo ""
print_success "Kiosk Mumble Client installed"
echo ""
echo "Service Management:"
echo "-------------------"
echo "Start service:   sudo systemctl start kiosk-mumble"
echo "Stop service:    sudo systemctl stop kiosk-mumble"
echo "Enable on boot:  sudo systemctl enable kiosk-mumble"
echo "View logs:       sudo journalctl -u kiosk-mumble -f"
echo "Service status:  sudo systemctl status kiosk-mumble"
echo ""
echo "Manual Testing:"
echo "---------------"
echo "Test audio:"
if [ -n "$MUMBLE_CHANNEL" ]; then
    echo "  sudo -u $TARGET_USER $USER_HOME/bin/kiosk-mumble \\"
    echo "    -server $MUMBLE_SERVER:$MUMBLE_PORT \\"
    echo "    -username $MUMBLE_USERNAME \\"
    echo "    -channel \"$MUMBLE_CHANNEL\" \\"
    echo "    -vad"
else
    echo "  sudo -u $TARGET_USER $USER_HOME/bin/kiosk-mumble \\"
    echo "    -server $MUMBLE_SERVER:$MUMBLE_PORT \\"
    echo "    -username $MUMBLE_USERNAME \\"
    echo "    -vad"
fi
echo ""
echo "Audio Troubleshooting:"
echo "----------------------"
echo "Check audio devices:"
echo "  pactl list short sinks"
echo "  pactl list short sources"
echo ""
echo "Test microphone:"
echo "  arecord -d 5 test.wav && aplay test.wav"
echo ""
print_warning "Note: User must log out and back in for group changes to take effect!"
echo ""

read -p "Enable and start service now? (Y/n): " START_NOW
if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
    sudo systemctl enable kiosk-mumble
    sudo systemctl start kiosk-mumble
    print_success "Service enabled and started"
    echo ""
    echo "Checking status..."
    sleep 2
    sudo systemctl status kiosk-mumble --no-pager
fi

echo ""
print_info "Installation complete! Check logs with: sudo journalctl -u kiosk-mumble -f"
echo ""
