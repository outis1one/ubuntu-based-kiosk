#!/bin/bash
################################################################################
# Electron Update Script for Ubuntu Based Kiosk (UBK)
# Safely updates the Electron version with backup and restore capabilities
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

KIOSK_USER="${KIOSK_USER:-kiosk}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR=""

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

print_header() {
    echo ""
    echo "========================================"
    echo "  $*"
    echo "========================================"
    echo ""
}

################################################################################
# Find Kiosk Installation
################################################################################

find_kiosk_dir() {
    local DETECTED_DIR=""

    # Method 1: Check default kiosk user home
    if id "$KIOSK_USER" &>/dev/null; then
        local kiosk_home=$(eval echo ~$KIOSK_USER)
        # Use sudo to check file since /home/kiosk may have restricted permissions
        if sudo test -f "$kiosk_home/kiosk-app/main.js" 2>/dev/null; then
            DETECTED_DIR="$kiosk_home/kiosk-app"
        fi
    fi

    # Method 2: Search all /home directories
    if [ -z "$DETECTED_DIR" ]; then
        for user_home in /home/*; do
            # Use sudo to check file in case of restricted permissions
            if sudo test -f "$user_home/kiosk-app/main.js" 2>/dev/null; then
                DETECTED_DIR="$user_home/kiosk-app"
                break
            fi
        done
    fi

    # Method 3: Check systemd service
    if [ -z "$DETECTED_DIR" ]; then
        if systemctl list-units --all kiosk.service 2>/dev/null | grep -q kiosk.service; then
            local service_dir=$(systemctl show -p WorkingDirectory kiosk.service 2>/dev/null | cut -d= -f2)
            if [ -n "$service_dir" ] && sudo test -f "$service_dir/main.js" 2>/dev/null; then
                DETECTED_DIR="$service_dir"
            fi
        fi
    fi

    # Method 4: Check for running electron process
    if [ -z "$DETECTED_DIR" ]; then
        local electron_path=$(ps aux | grep -E "electron.*main.js" | grep -v grep | head -1 | awk '{for(i=11;i<=NF;i++) if($i ~ /^\//) {print $i; exit}}')
        if [ -n "$electron_path" ]; then
            # Extract directory from electron path (e.g., /home/kiosk/kiosk-app/node_modules/electron/dist/electron -> /home/kiosk/kiosk-app)
            local app_dir=$(echo "$electron_path" | sed 's|/node_modules/electron.*||')
            if [ -n "$app_dir" ] && sudo test -f "$app_dir/main.js" 2>/dev/null; then
                DETECTED_DIR="$app_dir"
            fi
        fi
    fi

    echo "$DETECTED_DIR"
}

################################################################################
# Get Current Electron Version
################################################################################

get_current_electron_version() {
    local kiosk_dir="$1"
    local package_json="$kiosk_dir/package.json"

    if ! sudo test -f "$package_json" 2>/dev/null; then
        echo "unknown"
        return 1
    fi

    # Try to get version from package.json (use sudo to read)
    local version=$(sudo grep -oP '"electron"\s*:\s*"\^?\K[0-9.]+' "$package_json" 2>/dev/null || echo "")

    if [ -z "$version" ]; then
        # Try to get from installed node_modules
        local electron_pkg="$kiosk_dir/node_modules/electron/package.json"
        if sudo test -f "$electron_pkg" 2>/dev/null; then
            version=$(sudo grep -oP '"version"\s*:\s*"\K[0-9.]+' "$electron_pkg" 2>/dev/null || echo "unknown")
        else
            version="not installed"
        fi
    fi

    echo "$version"
}

################################################################################
# Check if Electron is Actually Running
################################################################################

check_electron_running() {
    if pgrep -f "electron.*main.js" >/dev/null 2>&1; then
        return 0
    elif pgrep -f "node.*electron" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Get Latest Stable Electron Version from npm
################################################################################

get_latest_electron_version() {
    log_info "Fetching latest stable Electron version from npm..." >&2

    # Try multiple methods to get the latest version
    local version=""

    # Method 1: Use npm view
    version=$(npm view electron version 2>/dev/null || echo "")

    # Method 2: Use curl to npm registry if npm view fails
    if [ -z "$version" ]; then
        version=$(curl -s https://registry.npmjs.org/electron/latest 2>/dev/null | grep -oP '"version"\s*:\s*"\K[0-9.]+' || echo "")
    fi

    # Method 3: Check GitHub releases as fallback
    if [ -z "$version" ]; then
        version=$(curl -s https://api.github.com/repos/electron/electron/releases/latest 2>/dev/null | grep -oP '"tag_name"\s*:\s*"v\K[0-9.]+' || echo "")
    fi

    if [ -z "$version" ]; then
        log_error "Failed to fetch latest Electron version" >&2
        echo "unknown"
        return 1
    fi

    echo "$version"
}

################################################################################
# Create Backup
################################################################################

create_backup() {
    local kiosk_dir="$1"
    local kiosk_owner=$(sudo stat -c '%U' "$kiosk_dir")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="${kiosk_dir}/backups/electron_backup_${timestamp}"

    log_info "Creating backup..."

    # Create backup directory
    sudo -u "$kiosk_owner" mkdir -p "$BACKUP_DIR"

    # Backup package.json and package-lock.json
    if sudo test -f "$kiosk_dir/package.json" 2>/dev/null; then
        sudo -u "$kiosk_owner" cp "$kiosk_dir/package.json" "$BACKUP_DIR/"
        log_success "Backed up package.json"
    fi

    if sudo test -f "$kiosk_dir/package-lock.json" 2>/dev/null; then
        sudo -u "$kiosk_owner" cp "$kiosk_dir/package-lock.json" "$BACKUP_DIR/"
        log_success "Backed up package-lock.json"
    fi

    # Create a list of installed packages
    if sudo test -d "$kiosk_dir/node_modules" 2>/dev/null; then
        sudo -u "$kiosk_owner" bash -c "ls -1 '$kiosk_dir/node_modules' > '$BACKUP_DIR/installed_packages.txt'"
        log_success "Created list of installed packages"
    fi

    # Save current Electron version
    local current_version=$(get_current_electron_version "$kiosk_dir")
    echo "$current_version" | sudo -u "$kiosk_owner" tee "$BACKUP_DIR/electron_version.txt" > /dev/null

    log_success "Backup created at: $BACKUP_DIR"
}

################################################################################
# Restore from Backup
################################################################################

show_restore_instructions() {
    local backup_dir="$1"

    echo ""
    echo "========================================"
    echo "  RESTORE INSTRUCTIONS"
    echo "========================================"
    echo ""
    echo "If you need to restore from backup, run these commands:"
    echo ""
    echo -e "${YELLOW}# Stop the kiosk service${NC}"
    echo "sudo systemctl stop kiosk"
    echo ""
    echo -e "${YELLOW}# Restore package.json${NC}"
    echo "sudo cp $backup_dir/package.json $KIOSK_DIR/"
    echo ""
    echo -e "${YELLOW}# Restore package-lock.json (if it exists)${NC}"
    echo "[ -f $backup_dir/package-lock.json ] && sudo cp $backup_dir/package-lock.json $KIOSK_DIR/"
    echo ""
    echo -e "${YELLOW}# Reinstall original Electron version${NC}"
    echo "cd $KIOSK_DIR"
    echo "sudo -u $KIOSK_USER npm install"
    echo ""
    echo -e "${YELLOW}# Restart the kiosk service${NC}"
    echo "sudo systemctl start kiosk"
    echo ""
    echo "Backup location: $backup_dir"
    echo ""
}

################################################################################
# Update Electron
################################################################################

update_electron() {
    local kiosk_dir="$1"
    local target_version="$2"
    local kiosk_owner="$3"

    log_info "Stopping kiosk display..."
    sudo systemctl stop lightdm || true
    sleep 2

    log_info "Updating Electron to version $target_version..."

    # Update package.json with new version
    sudo -u "$kiosk_owner" sed -i "s/\"electron\": \".*\"/\"electron\": \"^$target_version\"/" "$kiosk_dir/package.json"

    # Remove old electron installation
    if sudo test -d "$kiosk_dir/node_modules/electron" 2>/dev/null; then
        log_info "Removing old Electron installation..."
        sudo -u "$kiosk_owner" rm -rf "$kiosk_dir/node_modules/electron"
    fi

    # Install new version
    log_info "Installing Electron $target_version (this may take a few minutes)..."

    if sudo -u "$kiosk_owner" bash -c "cd '$kiosk_dir' && npm install electron@'$target_version'" 2>&1 | tee /tmp/electron_install.log; then
        log_success "Electron updated successfully to version $target_version"

        # Fix chrome-sandbox permissions
        local sandbox="$kiosk_dir/node_modules/electron/dist/chrome-sandbox"
        if sudo test -f "$sandbox" 2>/dev/null; then
            sudo chown root:root "$sandbox"
            sudo chmod 4755 "$sandbox"
            log_success "Fixed chrome-sandbox permissions"
        fi

        return 0
    else
        log_error "Failed to install Electron $target_version"
        log_error "Check /tmp/electron_install.log for details"
        return 1
    fi
}

################################################################################
# Main Script
################################################################################

main() {
    print_header "Electron Update Script for UBK"

    # Verify not running as root
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run this script with sudo"
        echo "Run as regular user: ./$0"
        echo "The script will prompt for sudo when needed for specific commands"
        exit 1
    fi

    # Find kiosk installation
    log_info "Searching for kiosk installation..."
    KIOSK_DIR=$(find_kiosk_dir)

    if [ -z "$KIOSK_DIR" ] || [ ! -d "$KIOSK_DIR" ]; then
        log_error "Kiosk installation not found!"
        echo ""
        echo "Searched locations:"
        echo "  - /home/$KIOSK_USER/kiosk-app"
        echo "  - /home/*/kiosk-app"
        echo "  - systemd kiosk.service working directory"
        echo ""
        log_error "Please ensure kiosk is installed first"
        exit 1
    fi

    log_success "Found kiosk at: $KIOSK_DIR"

    # Detect kiosk owner
    KIOSK_OWNER=$(stat -c '%U' "$KIOSK_DIR")
    log_info "Kiosk owner: $KIOSK_OWNER"
    echo ""

    # Check if Electron is running
    if check_electron_running; then
        log_success "Electron app is running"
    else
        log_warning "Electron app does not appear to be running"
        log_warning "The app may be stopped or the detection failed"
    fi
    echo ""

    # Get current version
    log_info "Checking current Electron version..."
    CURRENT_VERSION=$(get_current_electron_version "$KIOSK_DIR")

    if [ "$CURRENT_VERSION" = "not installed" ]; then
        log_error "Electron is not installed in $KIOSK_DIR/node_modules/"
        log_error "Please run the kiosk installation script first"
        exit 1
    elif [ "$CURRENT_VERSION" = "unknown" ]; then
        log_warning "Could not determine current Electron version"
    else
        log_success "Current Electron version: $CURRENT_VERSION"
    fi
    echo ""

    # Get latest version
    LATEST_VERSION=$(get_latest_electron_version)

    if [ "$LATEST_VERSION" = "unknown" ]; then
        log_error "Could not fetch latest Electron version"
        log_error "Please check your internet connection"
        exit 1
    fi

    log_success "Latest stable Electron version: $LATEST_VERSION"
    echo ""

    # Compare versions
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        log_success "You are already running the latest version!"
        echo ""
        read -p "Do you want to reinstall Electron $LATEST_VERSION? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update cancelled"
            exit 0
        fi
    fi

    # Show update summary
    print_header "UPDATE SUMMARY"
    echo "Current version: $CURRENT_VERSION"
    echo "Target version:  $LATEST_VERSION"
    echo "Installation:    $KIOSK_DIR"
    echo ""

    # Show breaking changes warning
    log_warning "IMPORTANT: Check for breaking changes!"
    echo ""
    echo "Before updating, review the Electron release notes:"
    echo "  https://www.electronjs.org/docs/latest/breaking-changes"
    echo ""
    echo "Major version changes may include:"
    echo "  - API changes that require code updates"
    echo "  - Node.js version updates"
    echo "  - Chromium version updates"
    echo "  - Deprecated feature removals"
    echo ""

    # Confirm update
    read -p "Have you reviewed the breaking changes and want to proceed? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        exit 0
    fi

    # Create backup
    print_header "CREATING BACKUP"
    create_backup "$KIOSK_DIR"
    echo ""

    # Show restore instructions
    show_restore_instructions "$BACKUP_DIR"

    # Final confirmation
    read -p "Proceed with Electron update to version $LATEST_VERSION? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        log_info "Backup preserved at: $BACKUP_DIR"
        exit 0
    fi

    # Perform update
    print_header "UPDATING ELECTRON"

    if update_electron "$KIOSK_DIR" "$LATEST_VERSION" "$KIOSK_OWNER"; then
        echo ""
        print_header "UPDATE SUCCESSFUL"

        # Verify new version
        NEW_VERSION=$(get_current_electron_version "$KIOSK_DIR")
        log_success "Electron updated from $CURRENT_VERSION to $NEW_VERSION"
        echo ""

        # Restart kiosk display
        read -p "Restart kiosk display now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restarting kiosk display..."
            sudo systemctl start lightdm
            sleep 3

            if systemctl is-active --quiet lightdm; then
                log_success "Kiosk display started successfully"
            else
                log_error "Kiosk display failed to start"
                log_error "Check logs with: sudo journalctl -u lightdm -n 50"
                echo ""
                log_warning "You may need to restore from backup"
                show_restore_instructions "$BACKUP_DIR"
            fi
        else
            log_info "Kiosk display not started"
            log_info "Start manually with: sudo systemctl start lightdm"
        fi

        echo ""
        log_success "Backup preserved at: $BACKUP_DIR"
        log_info "You can delete the backup after confirming everything works"

    else
        echo ""
        print_header "UPDATE FAILED"
        log_error "Electron update failed"
        echo ""
        log_warning "Attempting to restore from backup..."

        # Restore package.json
        if [ -f "$BACKUP_DIR/package.json" ]; then
            sudo cp "$BACKUP_DIR/package.json" "$KIOSK_DIR/"
            log_success "Restored package.json"
        fi

        # Reinstall original version
        log_info "Reinstalling original Electron version..."
        if sudo -u "$KIOSK_OWNER" bash -c "cd '$KIOSK_DIR' && npm install"; then
            log_success "Restored original Electron installation"

            # Restart kiosk display
            log_info "Restarting kiosk display..."
            sudo systemctl start lightdm
            log_success "Kiosk display restarted"
        else
            log_error "Failed to restore original installation"
            log_error "Manual intervention required"
            show_restore_instructions "$BACKUP_DIR"
        fi

        exit 1
    fi

    echo ""
    log_success "Done!"
}

# Run main function
main "$@"
