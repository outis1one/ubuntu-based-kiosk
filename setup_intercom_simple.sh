#!/bin/bash
################################################################################
###   UBK Mumble/Talkiepi Intercom Setup                                    ###
###   Simple CLI-based Installation                                         ###
################################################################################
#
# This script provides a lightweight intercom solution using:
#   - Murmur: The Mumble server
#   - talkiepi: A simple, lightweight barnard-based Mumble client
#
# Advantages over talkkonnect:
#   - Much simpler codebase and build process
#   - Fewer dependencies
#   - Direct CLI arguments for server, user, password, channel
#   - More stable and less fragile
#
################################################################################

VERSION="2.0.0"
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

check_talkiepi_status() {
    local installed=false
    local running=false

    if [[ -f /usr/local/bin/talkiepi ]] || [[ -f /etc/systemd/system/talkiepi.service ]]; then
        installed=true
        if systemctl is-active --quiet talkiepi; then
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
    sudo systemctl stop mumble-server 2>/dev/null || true
    sleep 2

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
    echo "═══════════════════════════════════════════════════════════════"

    pause
}

################################################################################
### TALKIEPI CLIENT INSTALLATION
################################################################################

install_talkiepi_with_config() {
    local server_addr="$1"
    local server_port="$2"
    local tp_user="$3"
    local tp_pass="$4"
    local tp_channel="$5"

    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   INSTALLING TALKIEPI CLIENT"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "talkiepi is a lightweight Mumble client based on barnard"
    echo "Much simpler and more stable than talkkonnect"
    echo

    local TARGET_USER="$KIOSK_USER"
    local TARGET_UID=$(id -u "$TARGET_USER")
    local TARGET_HOME="/home/$TARGET_USER"

    # Verify home directory exists
    if [ ! -d "$TARGET_HOME" ]; then
        log_error "Home directory does not exist: $TARGET_HOME"
        pause
        return 1
    fi

    # --- System Prep ------------------------------------------------------
    echo "[1/5] Installing system dependencies..."
    sudo apt update
    sudo apt install -y git golang libopenal-dev libopus-dev

    # --- Clone and Build Talkiepi -----------------------------------------
    echo "[2/5] Cloning talkiepi repository..."
    cd "$TARGET_HOME"
    if [ -d "talkiepi" ]; then
        sudo rm -rf talkiepi
    fi

    # Clone as the target user
    sudo -u "$TARGET_USER" git clone https://github.com/dchote/talkiepi.git
    cd talkiepi

    echo "[3/5] Building talkiepi..."
    export GOPATH="$TARGET_HOME/gocode"
    export GOBIN="$TARGET_HOME/bin"

    # Install gopus dependency
    sudo -u "$TARGET_USER" go get github.com/dchote/gopus

    # Build talkiepi
    sudo -u "$TARGET_USER" go build -o "$TARGET_HOME/bin/talkiepi" cmd/talkiepi/main.go

    if [ ! -f "$TARGET_HOME/bin/talkiepi" ]; then
        log_error "Build failed!"
        pause
        return 1
    fi

    # Stop any running instances
    if systemctl is-active --quiet talkiepi 2>/dev/null; then
        sudo systemctl stop talkiepi
    fi

    # Install binary
    sudo cp "$TARGET_HOME/bin/talkiepi" /usr/local/bin/talkiepi
    sudo chmod +x /usr/local/bin/talkiepi
    log_success "Binary installed to /usr/local/bin/talkiepi"

    # --- User Permissions -------------------------------------------------
    echo "[4/5] Setting up permissions..."
    if ! groups "$TARGET_USER" | grep -q audio; then
        sudo usermod -a -G audio "$TARGET_USER"
        log_success "Added $TARGET_USER to 'audio' group"
    fi

    # --- Create Systemd Service -------------------------------------------
    echo "[5/5] Creating systemd service..."

    # Build the command line arguments
    local TALKIEPI_ARGS="-server ${server_addr}:${server_port} -username ${tp_user}"

    if [[ -n "$tp_pass" ]]; then
        TALKIEPI_ARGS="$TALKIEPI_ARGS -password ${tp_pass}"
    fi

    if [[ -n "$tp_channel" ]]; then
        TALKIEPI_ARGS="$TALKIEPI_ARGS -channel ${tp_channel}"
    fi

    # Add insecure flag for local/self-signed certs
    TALKIEPI_ARGS="$TALKIEPI_ARGS -insecure"

    sudo tee /etc/systemd/system/talkiepi.service > /dev/null <<EOFSVC
[Unit]
Description=Talkiepi Lightweight Mumble Client
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_USER
WorkingDirectory=$TARGET_HOME
ExecStart=/usr/local/bin/talkiepi $TALKIEPI_ARGS
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment="XDG_RUNTIME_DIR=/run/user/$TARGET_UID"

[Install]
WantedBy=multi-user.target
EOFSVC

    sudo systemctl daemon-reload
    sudo systemctl enable talkiepi
    sudo systemctl start talkiepi

    sleep 3

    log_success "talkiepi installed successfully!"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Server: $server_addr:$server_port"
    echo "  Username: $tp_user"
    echo "  Channel: ${tp_channel:-Root}"
    echo "  Binary: /usr/local/bin/talkiepi"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    # Show status
    if systemctl is-active --quiet talkiepi; then
        log_success "Service is running"
        echo "View logs: sudo journalctl -u talkiepi -f"
    else
        log_warning "Service may have issues"
        echo "Check logs: sudo journalctl -u talkiepi -n 50"
    fi

    pause
}

install_talkiepi_only() {
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   TALKIEPI - CONNECT TO EXISTING SERVER"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    echo "Enter Murmur/Mumble server details:"
    read -r -p "Server address (IP or domain): " server_addr
    read -r -p "Port [64738]: " server_port
    server_port="${server_port:-64738}"
    read -r -p "Username: " tp_user
    read -r -s -p "Password (leave empty if none): " tp_pass
    echo
    read -r -p "Channel [Root]: " tp_channel
    tp_channel="${tp_channel:-Root}"

    install_talkiepi_with_config "$server_addr" "$server_port" "$tp_user" "$tp_pass" "$tp_channel"
}

install_murmur_and_talkiepi() {
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "   ALL-IN-ONE: SERVER + CLIENT"
    echo "═══════════════════════════════════════════════════════════════"
    echo

    echo "Installing Murmur server..."
    install_murmur_server

    echo
    echo "Now installing talkiepi client..."
    echo "Configuring to connect to local server..."

    # Auto-configure for local server
    AUTO_SERVER="127.0.0.1"
    AUTO_PORT="64738"
    read -r -p "Username for talkiepi [kiosk]: " tp_user
    tp_user="${tp_user:-kiosk}"
    read -r -s -p "Server password: " tp_pass
    echo

    install_talkiepi_with_config "$AUTO_SERVER" "$AUTO_PORT" "$tp_user" "$tp_pass" "Root"
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

toggle_talkiepi_service() {
    echo
    if systemctl is-active --quiet talkiepi; then
        echo "Stopping talkiepi..."
        sudo systemctl stop talkiepi
        log_success "talkiepi stopped"
    else
        echo "Starting talkiepi..."
        sudo systemctl start talkiepi
        sleep 2
        if systemctl is-active --quiet talkiepi; then
            log_success "talkiepi started"
        else
            log_error "Failed to start - check logs: sudo journalctl -u talkiepi"
        fi
    fi
    pause
}

################################################################################
### LOGS AND DIAGNOSTICS
################################################################################

view_talkiepi_logs() {
    echo
    echo "Recent talkiepi logs:"
    echo "═══════════════════════════════════════════════════════════════"
    sudo journalctl -u talkiepi -n 50 --no-pager
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

uninstall_talkiepi() {
    echo
    read -r -p "Uninstall talkiepi? (yes/no): " confirm
    [[ "$confirm" != "yes" ]] && return

    echo "Uninstalling talkiepi..."

    # Stop and disable service
    if systemctl is-active --quiet talkiepi 2>/dev/null; then
        sudo systemctl stop talkiepi
    fi

    if systemctl is-enabled --quiet talkiepi 2>/dev/null; then
        sudo systemctl disable talkiepi
    fi

    # Remove systemd service file
    if [[ -f /etc/systemd/system/talkiepi.service ]]; then
        sudo rm -f /etc/systemd/system/talkiepi.service
        sudo systemctl daemon-reload
    fi

    # Remove binary
    if [[ -f /usr/local/bin/talkiepi ]]; then
        sudo rm -f /usr/local/bin/talkiepi
    fi

    # Remove source directory
    read -r -p "Also remove source directory? (y/n): " remove_source
    if [[ "$remove_source" =~ ^[Yy]$ ]] && [[ -d "/home/$KIOSK_USER/talkiepi" ]]; then
        sudo rm -rf "/home/$KIOSK_USER/talkiepi"
        sudo rm -rf "/home/$KIOSK_USER/gocode"
        sudo rm -rf "/home/$KIOSK_USER/bin"
    fi

    log_success "talkiepi uninstalled"
    pause
}

################################################################################
### MAIN MENU
################################################################################

show_status() {
    local murmur_status=$(check_murmur_status)
    local murmur_installed=$(echo "$murmur_status" | cut -d: -f1)
    local murmur_running=$(echo "$murmur_status" | cut -d: -f2)

    local tp_status=$(check_talkiepi_status)
    local tp_installed=$(echo "$tp_status" | cut -d: -f1)
    local tp_running=$(echo "$tp_status" | cut -d: -f2)

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

    # talkiepi status
    if [[ "$tp_installed" == "true" ]]; then
        echo "talkiepi Client: ✓ Installed"
        if [[ "$tp_running" == "true" ]]; then
            echo "  Status: Running"
        else
            echo "  Status: Stopped"
        fi
        echo
    else
        echo "talkiepi Client: Not installed"
        echo
    fi
}

main_menu() {
    while true; do
        clear
        echo "═══════════════════════════════════════════════════════════════"
        echo "   UBK INTERCOM SETUP v${VERSION}"
        echo "   Mumble/Talkiepi (Lightweight & Stable)"
        echo "═══════════════════════════════════════════════════════════════"

        show_status

        local murmur_status=$(check_murmur_status)
        local murmur_installed=$(echo "$murmur_status" | cut -d: -f1)
        local murmur_running=$(echo "$murmur_status" | cut -d: -f2)

        local tp_status=$(check_talkiepi_status)
        local tp_installed=$(echo "$tp_status" | cut -d: -f1)
        local tp_running=$(echo "$tp_status" | cut -d: -f2)

        echo "═══════════════════════════════════════════════════════════════"
        echo "   INSTALLATION OPTIONS"
        echo "═══════════════════════════════════════════════════════════════"

        local menu_num=1

        # Installation options (shown when nothing installed)
        if [[ "$murmur_installed" == "false" && "$tp_installed" == "false" ]]; then
            echo "  $menu_num. Install All-in-One (Server + Client)"
            local opt_all_in_one=$menu_num
            ((menu_num++))
            echo "  $menu_num. Install Murmur Server Only"
            local opt_server_only=$menu_num
            ((menu_num++))
            echo "  $menu_num. Install talkiepi Client Only"
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

            # talkiepi management options
            if [[ "$tp_installed" == "true" ]]; then
                echo
                echo "talkiepi Client:"
                if [[ "$tp_running" == "true" ]]; then
                    echo "  $menu_num. Stop talkiepi"
                else
                    echo "  $menu_num. Start talkiepi"
                fi
                local opt_tp_toggle=$menu_num
                ((menu_num++))

                echo "  $menu_num. View talkiepi Logs"
                local opt_tp_logs=$menu_num
                ((menu_num++))

                echo "  $menu_num. Uninstall talkiepi"
                local opt_tp_uninstall=$menu_num
                ((menu_num++))
            else
                echo
                echo "  $menu_num. Install talkiepi Client"
                local opt_install_tp=$menu_num
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
                install_murmur_and_talkiepi
                ;;
            ${opt_server_only:-})
                install_murmur_server
                ;;
            ${opt_client_only:-})
                install_talkiepi_only
                ;;
            ${opt_install_murmur:-})
                install_murmur_server
                ;;
            ${opt_install_tp:-})
                install_talkiepi_only
                ;;
            ${opt_murmur_toggle:-})
                toggle_murmur_service
                ;;
            ${opt_murmur_logs:-})
                view_murmur_logs
                ;;
            ${opt_murmur_uninstall:-})
                uninstall_murmur
                ;;
            ${opt_tp_toggle:-})
                toggle_talkiepi_service
                ;;
            ${opt_tp_logs:-})
                view_talkiepi_logs
                ;;
            ${opt_tp_uninstall:-})
                uninstall_talkiepi
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
    echo "Please run as: ./setup_intercom_simple.sh"
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
