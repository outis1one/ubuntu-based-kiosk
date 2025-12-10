#!/bin/bash

################################################################################
# UBK Kiosk Installation Script v0.9.9
# 
# Purpose: Install and configure UBK kiosk with addon support
# Features: Easy Asterisk integration, Intercom support, Addon menu system
# Last Updated: 2025-12-09
# Author: outis1one
#
# Changes in v0.9.9:
# - Added Easy Asterisk addon integration
# - Implemented intercom option in addons menu
# - Enhanced addon management system
# - Improved configuration handling
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_VERSION="0.9.9"
KIOSK_HOME="${KIOSK_HOME:-.}"
ADDON_DIR="${KIOSK_HOME}/addons"
CONFIG_DIR="${KIOSK_HOME}/config"
LOG_FILE="${KIOSK_HOME}/install_kiosk_v${SCRIPT_VERSION}.log"

# Ensure directories exist
mkdir -p "$ADDON_DIR"
mkdir -p "$CONFIG_DIR"

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

################################################################################
# System Check Functions
################################################################################

check_dependencies() {
    log_info "Checking system dependencies..."
    
    local missing_deps=()
    local required_packages=("curl" "wget" "git" "tar" "gzip")
    
    for pkg in "${required_packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_deps+=("$pkg")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warning "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing missing packages..."
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${missing_deps[@]}"
        else
            log_error "Unable to install packages. Please install manually: ${missing_deps[*]}"
            return 1
        fi
    fi
    
    log_success "All dependencies satisfied"
    return 0
}

check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check OS
    if [[ ! "$OSTYPE" =~ ^linux ]]; then
        log_error "This script requires Linux"
        return 1
    fi
    
    # Check disk space (minimum 500MB)
    local available_space=$(df "$KIOSK_HOME" | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 512000 ]; then
        log_error "Insufficient disk space. Minimum 500MB required."
        return 1
    fi
    
    log_success "System requirements met"
    return 0
}

################################################################################
# Addon Management Functions
################################################################################

install_addon() {
    local addon_name="$1"
    local addon_url="$2"
    
    log_info "Installing addon: $addon_name"
    
    local addon_path="${ADDON_DIR}/${addon_name}"
    mkdir -p "$addon_path"
    
    if [ -n "$addon_url" ]; then
        log_info "Downloading addon from: $addon_url"
        curl -sSL "$addon_url" | tar -xz -C "$addon_path" --strip-components=1
    fi
    
    # Initialize addon configuration
    if [ -f "${addon_path}/init.sh" ]; then
        bash "${addon_path}/init.sh"
    fi
    
    log_success "Addon $addon_name installed successfully"
}

################################################################################
# Easy Asterisk Integration
################################################################################

install_easy_asterisk() {
    log_info "Installing Easy Asterisk addon..."
    
    local asterisk_addon_path="${ADDON_DIR}/easy_asterisk"
    mkdir -p "$asterisk_addon_path"
    
    # Create Easy Asterisk configuration
    cat > "${asterisk_addon_path}/config.conf" <<'EOF'
[easy_asterisk]
enabled = true
version = 1.0
description = Easy Asterisk Integration for UBK Kiosk

[asterisk_server]
host = localhost
port = 5060
protocol = SIP

[features]
call_forwarding = true
voicemail_integration = true
conference_support = true
caller_id_customization = true

[security]
enable_auth = true
enable_encryption = false
allowed_ips = localhost,127.0.0.1

[logging]
level = INFO
output_file = /var/log/ubk_asterisk.log
EOF

    # Create initialization script
    cat > "${asterisk_addon_path}/init.sh" <<'EOF'
#!/bin/bash

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${ADDON_DIR}/config.conf"

echo "[Easy Asterisk] Initializing addon..."

# Check if Asterisk is installed
if ! command -v asterisk &> /dev/null; then
    echo "[Easy Asterisk] Warning: Asterisk not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y asterisk asterisk-dev
fi

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source <(grep -E '^\[|^[a-zA-Z_]' "$CONFIG_FILE")
    echo "[Easy Asterisk] Configuration loaded"
fi

# Initialize Asterisk integration
echo "[Easy Asterisk] Starting Asterisk daemon..."
sudo systemctl restart asterisk || true

echo "[Easy Asterisk] Addon initialized successfully"
EOF

    chmod +x "${asterisk_addon_path}/init.sh"
    
    # Run initialization
    bash "${asterisk_addon_path}/init.sh"
    
    log_success "Easy Asterisk addon installed"
}

################################################################################
# Intercom Integration (Easy Asterisk)
################################################################################

# GitHub repository details
EASY_ASTERISK_REPO="outis1one/easy-asterisk"
EASY_ASTERISK_RAW_URL="https://raw.githubusercontent.com/${EASY_ASTERISK_REPO}/main"
EASY_ASTERISK_API_URL="https://api.github.com/repos/${EASY_ASTERISK_REPO}/contents"

# Local installation paths
EASY_ASTERISK_INSTALL_DIR="/opt/easy-asterisk"
EASY_ASTERISK_VERSION_FILE="${EASY_ASTERISK_INSTALL_DIR}/.version"
EASY_ASTERISK_CONFIG_BACKUP="${EASY_ASTERISK_INSTALL_DIR}/config_backup"

################################################################################
# Function: get_latest_easy_asterisk_version
# Description: Get the latest version of easy-asterisk from GitHub
# Returns: Version string (e.g., "1.2.3") or empty string on failure
################################################################################
get_latest_easy_asterisk_version() {
    log_info "Checking for latest Easy Asterisk version..."

    # Try to get file list from GitHub API
    local files_json=$(curl -s "${EASY_ASTERISK_API_URL}" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$files_json" ]; then
        log_warning "Could not fetch file list from GitHub API"
        return 1
    fi

    # Extract easy-asterisk-v*.sh files and find the latest version
    local latest_version=$(echo "$files_json" | grep -oP 'easy-asterisk-v\K[0-9]+\.[0-9]+\.[0-9]+(?=\.sh)' | sort -V | tail -1)

    if [ -z "$latest_version" ]; then
        log_warning "No version files found in repository"
        return 1
    fi

    echo "$latest_version"
    return 0
}

################################################################################
# Function: get_installed_easy_asterisk_version
# Description: Get the currently installed version of easy-asterisk
# Returns: Version string or empty if not installed
################################################################################
get_installed_easy_asterisk_version() {
    if [ -f "$EASY_ASTERISK_VERSION_FILE" ]; then
        cat "$EASY_ASTERISK_VERSION_FILE"
        return 0
    fi

    echo ""
    return 1
}

################################################################################
# Function: backup_easy_asterisk_configs
# Description: Backup existing configuration files before update
# Returns: 0 on success, 1 on failure
################################################################################
backup_easy_asterisk_configs() {
    log_info "Backing up Easy Asterisk configurations..."

    if [ ! -d "$EASY_ASTERISK_INSTALL_DIR" ]; then
        log_info "No existing installation to backup"
        return 0
    fi

    # Create backup directory with timestamp
    local backup_dir="${EASY_ASTERISK_CONFIG_BACKUP}/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup common config directories and files
    for item in config etc *.conf *.cfg; do
        if [ -e "${EASY_ASTERISK_INSTALL_DIR}/${item}" ]; then
            cp -r "${EASY_ASTERISK_INSTALL_DIR}/${item}" "$backup_dir/" 2>/dev/null || true
        fi
    done

    # Also backup Asterisk configs if they exist
    if [ -d "/etc/asterisk" ]; then
        mkdir -p "${backup_dir}/asterisk_etc"
        cp -r /etc/asterisk/*.conf "${backup_dir}/asterisk_etc/" 2>/dev/null || true
    fi

    log_success "Configuration backup created at: $backup_dir"
    return 0
}

################################################################################
# Function: restore_easy_asterisk_configs
# Description: Restore configuration files after update
# Parameters: $1 - Backup directory path
# Returns: 0 on success, 1 on failure
################################################################################
restore_easy_asterisk_configs() {
    local backup_dir="$1"

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        log_info "No backup to restore"
        return 0
    fi

    log_info "Restoring Easy Asterisk configurations..."

    # Restore backed up items
    for item in $(ls -A "$backup_dir"); do
        if [ "$item" != "asterisk_etc" ]; then
            cp -r "${backup_dir}/${item}" "${EASY_ASTERISK_INSTALL_DIR}/" 2>/dev/null || true
        fi
    done

    # Restore Asterisk configs if they were backed up
    if [ -d "${backup_dir}/asterisk_etc" ]; then
        cp -r "${backup_dir}/asterisk_etc"/*.conf /etc/asterisk/ 2>/dev/null || true
    fi

    log_success "Configuration restored"
    return 0
}

################################################################################
# Function: download_and_install_easy_asterisk
# Description: Download and run the Easy Asterisk installation script
# Parameters: $1 - Version to install
# Returns: 0 on success, 1 on failure
################################################################################
download_and_install_easy_asterisk() {
    local version="$1"
    local script_name="easy-asterisk-v${version}.sh"
    local script_url="${EASY_ASTERISK_RAW_URL}/${script_name}"
    local temp_script="/tmp/${script_name}"

    log_info "Downloading Easy Asterisk v${version}..."

    # Download the installation script
    if ! curl -fsSL "$script_url" -o "$temp_script"; then
        log_error "Failed to download Easy Asterisk installation script"
        log_error "URL: $script_url"
        return 1
    fi

    # Verify the script was downloaded
    if [ ! -f "$temp_script" ] || [ ! -s "$temp_script" ]; then
        log_error "Downloaded script is empty or missing"
        return 1
    fi

    # Make script executable
    chmod +x "$temp_script"

    log_info "Running Easy Asterisk installation script..."
    log_info "This may take several minutes..."

    # Run the installation script
    if bash "$temp_script"; then
        log_success "Easy Asterisk installation completed"

        # Save version information
        mkdir -p "$EASY_ASTERISK_INSTALL_DIR"
        echo "$version" > "$EASY_ASTERISK_VERSION_FILE"

        # Clean up temp file
        rm -f "$temp_script"
        return 0
    else
        log_error "Easy Asterisk installation failed"
        rm -f "$temp_script"
        return 1
    fi
}

################################################################################
# Function: install_intercom
# Description: Install or update Easy Asterisk Intercom addon
# Returns: 0 on success, 1 on failure
################################################################################
install_intercom() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Easy Asterisk Intercom Setup${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""

    # Get latest version from GitHub
    local latest_version=$(get_latest_easy_asterisk_version)

    if [ -z "$latest_version" ]; then
        log_error "Could not determine latest version"
        log_error "Please check your internet connection and that the repository is accessible"
        log_error "Repository: https://github.com/${EASY_ASTERISK_REPO}"
        return 1
    fi

    log_info "Latest version available: v${latest_version}"

    # Check if already installed
    local installed_version=$(get_installed_easy_asterisk_version)

    if [ -n "$installed_version" ]; then
        log_info "Currently installed version: v${installed_version}"

        # Compare versions
        if [ "$installed_version" = "$latest_version" ]; then
            echo ""
            log_info "Easy Asterisk v${installed_version} is already installed (latest version)"
            echo ""
            read -p "Do you want to re-run the installation? (y/N): " rerun_choice

            if [[ ! "$rerun_choice" =~ ^[Yy]$ ]]; then
                log_info "Installation cancelled"
                return 0
            fi

            log_info "Re-running installation (configs will be preserved)..."
        else
            echo ""
            log_info "Update available: v${installed_version} → v${latest_version}"
            echo ""
            read -p "Do you want to update? (Y/n): " update_choice

            if [[ "$update_choice" =~ ^[Nn]$ ]]; then
                log_info "Update cancelled"
                return 0
            fi

            log_info "Updating Easy Asterisk..."
        fi

        # Backup existing configurations
        backup_easy_asterisk_configs
        local backup_dir=$(ls -td "${EASY_ASTERISK_CONFIG_BACKUP}"/* 2>/dev/null | head -1)
    else
        log_info "Easy Asterisk is not currently installed"
        echo ""
        read -p "Do you want to install Easy Asterisk v${latest_version}? (Y/n): " install_choice

        if [[ "$install_choice" =~ ^[Nn]$ ]]; then
            log_info "Installation cancelled"
            return 0
        fi
    fi

    # Download and install
    if download_and_install_easy_asterisk "$latest_version"; then
        # Restore configurations if this was an update/rerun
        if [ -n "$backup_dir" ]; then
            restore_easy_asterisk_configs "$backup_dir"
        fi

        echo ""
        log_success "Easy Asterisk Intercom is ready!"
        log_info "Installation directory: $EASY_ASTERISK_INSTALL_DIR"
        log_info "Version: v${latest_version}"

        if [ -n "$installed_version" ] && [ "$installed_version" != "$latest_version" ]; then
            log_success "Successfully updated from v${installed_version} to v${latest_version}"
            log_info "Your configurations have been preserved"
        fi

        echo ""
        return 0
    else
        log_error "Installation failed"

        # Attempt to restore from backup if update failed
        if [ -n "$backup_dir" ]; then
            log_warning "Attempting to restore previous configuration..."
            restore_easy_asterisk_configs "$backup_dir"
        fi

        return 1
    fi
}

################################################################################
# Addon Menu
################################################################################

display_addon_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}================================${NC}"
        echo -e "${BLUE}   UBK Kiosk v${SCRIPT_VERSION} Addon Menu${NC}"
        echo -e "${BLUE}================================${NC}"
        echo "1) Install Easy Asterisk"
        echo "2) Install/Update Intercom (Easy Asterisk)"
        echo "3) Install Custom Addon"
        echo "4) List Installed Addons"
        echo "5) Configure Easy Asterisk"
        echo "6) Configure Intercom"
        echo "7) View Addon Logs"
        echo "8) Return to Main Menu"
        echo "9) Exit"
        echo -e "${BLUE}================================${NC}"
        
        read -p "Select option: " addon_choice
        
        case $addon_choice in
            1)
                install_easy_asterisk
                ;;
            2)
                install_intercom
                ;;
            3)
                read -p "Enter addon name: " addon_name
                read -p "Enter addon URL (leave blank for local): " addon_url
                install_addon "$addon_name" "$addon_url"
                ;;
            4)
                list_addons
                ;;
            5)
                configure_easy_asterisk
                ;;
            6)
                configure_intercom
                ;;
            7)
                view_addon_logs
                ;;
            8)
                return
                ;;
            9)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_warning "Invalid option"
                ;;
        esac
    done
}

list_addons() {
    log_info "Installed addons:"
    echo ""
    
    if [ -d "$ADDON_DIR" ] && [ "$(ls -A $ADDON_DIR)" ]; then
        ls -1 "$ADDON_DIR" | while read addon; do
            if [ -f "${ADDON_DIR}/${addon}/config.conf" ]; then
                local enabled=$(grep "^enabled" "${ADDON_DIR}/${addon}/config.conf" | cut -d'=' -f2 | tr -d ' ')
                if [ "$enabled" = "true" ]; then
                    echo -e "  ${GREEN}✓${NC} $addon (enabled)"
                else
                    echo -e "  ${RED}✗${NC} $addon (disabled)"
                fi
            fi
        done
    else
        log_warning "No addons installed"
    fi
    
    echo ""
}

configure_easy_asterisk() {
    local config_file="${ADDON_DIR}/easy_asterisk/config.conf"
    
    if [ ! -f "$config_file" ]; then
        log_error "Easy Asterisk not installed"
        return
    fi
    
    log_info "Configuring Easy Asterisk..."
    
    read -p "Enter Asterisk server host [localhost]: " asterisk_host
    asterisk_host="${asterisk_host:-localhost}"
    
    read -p "Enter Asterisk server port [5060]: " asterisk_port
    asterisk_port="${asterisk_port:-5060}"
    
    sed -i "s/^host = .*/host = $asterisk_host/" "$config_file"
    sed -i "s/^port = .*/port = $asterisk_port/" "$config_file"
    
    log_success "Easy Asterisk configuration updated"
}

configure_intercom() {
    # Check if Easy Asterisk is installed
    if [ ! -d "$EASY_ASTERISK_INSTALL_DIR" ]; then
        log_error "Easy Asterisk Intercom is not installed"
        log_info "Please install it first using option 2 from the Addons menu"
        return 1
    fi

    local installed_version=$(get_installed_easy_asterisk_version)

    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Easy Asterisk Configuration${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    log_info "Installed version: v${installed_version}"
    log_info "Installation directory: $EASY_ASTERISK_INSTALL_DIR"
    echo ""

    # Check if the easy-asterisk installation has a configuration script
    if [ -x "${EASY_ASTERISK_INSTALL_DIR}/configure.sh" ]; then
        log_info "Running Easy Asterisk configuration script..."
        bash "${EASY_ASTERISK_INSTALL_DIR}/configure.sh"
    elif [ -d "/etc/asterisk" ]; then
        log_info "Asterisk configuration files are located in /etc/asterisk/"
        echo ""
        echo "Common configuration files:"
        echo "  - /etc/asterisk/sip.conf (SIP configuration)"
        echo "  - /etc/asterisk/extensions.conf (Dialplan)"
        echo "  - /etc/asterisk/pjsip.conf (PJSIP configuration)"
        echo ""
        read -p "Do you want to edit a configuration file? (y/N): " edit_choice

        if [[ "$edit_choice" =~ ^[Yy]$ ]]; then
            echo ""
            echo "Available configuration files:"
            ls -1 /etc/asterisk/*.conf 2>/dev/null | nl
            echo ""
            read -p "Enter file number to edit (or q to cancel): " file_num

            if [[ "$file_num" =~ ^[0-9]+$ ]]; then
                local config_file=$(ls -1 /etc/asterisk/*.conf 2>/dev/null | sed -n "${file_num}p")
                if [ -f "$config_file" ]; then
                    ${EDITOR:-nano} "$config_file"
                    log_success "Configuration file edited: $config_file"
                    log_info "Restarting Asterisk to apply changes..."
                    systemctl restart asterisk
                else
                    log_error "Invalid file selection"
                fi
            fi
        fi
    else
        log_warning "No configuration interface found"
        log_info "You may need to manually configure Easy Asterisk"
    fi

    echo ""
}

view_addon_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        log_warning "No logs available yet"
        return
    fi
    
    log_info "Recent addon activity:"
    echo ""
    tail -n 20 "$LOG_FILE"
    echo ""
}

################################################################################
# Main Installation Functions
################################################################################

install_kiosk_base() {
    log_info "Installing UBK Kiosk base system..."
    
    # Create directory structure
    mkdir -p "${KIOSK_HOME}/bin"
    mkdir -p "${KIOSK_HOME}/lib"
    mkdir -p "${KIOSK_HOME}/data"
    mkdir -p "${KIOSK_HOME}/logs"
    
    # Create main configuration file
    cat > "${CONFIG_DIR}/kiosk.conf" <<EOF
[kiosk]
name = UBK Kiosk
version = ${SCRIPT_VERSION}
installed_date = $(date -u +'%Y-%m-%d %H:%M:%S')
installed_by = ${USER}

[system]
home_directory = ${KIOSK_HOME}
addon_directory = ${ADDON_DIR}
config_directory = ${CONFIG_DIR}
log_file = ${LOG_FILE}

[services]
enable_asterisk = false
enable_intercom = false
enable_webui = true

[ports]
webui_port = 8080
asterisk_port = 5060
intercom_port = 8888
EOF

    log_success "Kiosk base system installed"
}

show_main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}================================${NC}"
        echo -e "${BLUE}   UBK Kiosk v${SCRIPT_VERSION} Installation${NC}"
        echo -e "${BLUE}================================${NC}"
        echo "1) Install Kiosk Base System"
        echo "2) Manage Addons"
        echo "3) System Status"
        echo "4) View Configuration"
        echo "5) View Logs"
        echo "6) Reset Configuration"
        echo "7) Exit"
        echo -e "${BLUE}================================${NC}"
        
        read -p "Select option: " main_choice
        
        case $main_choice in
            1)
                install_kiosk_base
                ;;
            2)
                display_addon_menu
                ;;
            3)
                show_system_status
                ;;
            4)
                show_configuration
                ;;
            5)
                view_addon_logs
                ;;
            6)
                reset_configuration
                ;;
            7)
                log_info "Exiting installation script"
                exit 0
                ;;
            *)
                log_warning "Invalid option"
                ;;
        esac
    done
}

show_system_status() {
    log_info "System Status:"
    echo ""
    echo "UBK Kiosk Version: $SCRIPT_VERSION"
    echo "Installation Directory: $KIOSK_HOME"
    echo "Addon Directory: $ADDON_DIR"
    echo "Configuration Directory: $CONFIG_DIR"
    echo ""
    echo "Installed Addons:"
    list_addons
    
    echo "System Information:"
    echo "  OS: $(uname -s)"
    echo "  Kernel: $(uname -r)"
    echo "  CPU Cores: $(nproc)"
    echo "  Memory: $(free -h | grep Mem | awk '{print $2}')"
    echo ""
}

show_configuration() {
    local config_file="${CONFIG_DIR}/kiosk.conf"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found"
        return
    fi
    
    log_info "Current Configuration:"
    echo ""
    cat "$config_file"
    echo ""
}

reset_configuration() {
    read -p "Are you sure you want to reset the configuration? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        rm -rf "${CONFIG_DIR}"/*
        rm -rf "${ADDON_DIR}"/*
        log_success "Configuration reset"
    else
        log_warning "Reset cancelled"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    # Initialize log
    {
        echo "================================================================================"
        echo "UBK Kiosk Installation Script v${SCRIPT_VERSION}"
        echo "Started: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
        echo "User: ${USER}"
        echo "================================================================================"
    } >> "$LOG_FILE"
    
    log_info "Starting UBK Kiosk installation v${SCRIPT_VERSION}"
    
    # Run system checks
    if ! check_system_requirements; then
        log_error "System requirements not met"
        exit 1
    fi
    
    if ! check_dependencies; then
        log_error "Failed to install dependencies"
        exit 1
    fi
    
    log_success "Pre-installation checks completed"
    
    # Display main menu
    show_main_menu
}

# Run main function
main "$@"
