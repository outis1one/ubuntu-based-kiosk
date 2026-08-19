#!/bin/bash
################################################################################
# menus/advanced_upgrade.sh - "Upgrade" (Advanced): pull the latest code
# from git and re-apply provisioning, plus an on-demand Electron update.
#
# ubuntu-based-kiosk.sh's Upgrade extracted fresh copies of main.js/
# preload.js/etc from its own heredocs on every run - the modular tool
# has no heredocs to extract from. kiosk-app/ and provision/files/ are
# real files in this git checkout, so "get whatever's new" is just
# `git pull` followed by re-running the same steps lib/provision.sh
# already has for a fresh install - reused here, not reimplemented,
# minus the interactive first-run settings wizard and the "reboot now"
# prompt (upgrading shouldn't re-ask sites/hotspot/vconsoles or reboot
# the whole machine). Electron itself isn't versioned by this repo, so
# checking for a newer Electron is a separate step: the existing,
# already-tested action_update_electron (menus/advanced_electron.sh),
# reused as-is rather than duplicated.
#
# Depends on: lib/menu.sh, lib/config.sh, lib/electron.sh,
# lib/provision.sh, menus/advanced_electron.sh being sourced first.
################################################################################

advanced_upgrade_status() {
    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        local branch rev
        branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        rev=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "Installed from git: $branch @ $rev"
    else
        echo "Installed from git: not a git checkout (upgrade unavailable)"
    fi
}

advanced_upgrade_menu_builder() {
    MENU_LABELS=("Check for and apply updates")
    MENU_HANDLERS=(action_upgrade)
}

advanced_upgrade_menu() {
    run_menu "UPGRADE" advanced_upgrade_menu_builder advanced_upgrade_status
}

################################################################################
# Actions
################################################################################

action_upgrade() {
    echo
    if ! command -v git &>/dev/null; then
        log_error "git is not installed - can't check for updates"
        pause
        return 1
    fi

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        log_error "$SCRIPT_DIR is not a git checkout - re-clone the repo to get this feature"
        pause
        return 1
    fi

    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
        log_error "Local changes in $SCRIPT_DIR - commit or discard them first, then retry"
        pause
        return 1
    fi

    log_info "Checking for updates..."
    if ! git -C "$SCRIPT_DIR" fetch origin; then
        log_error "Could not reach GitHub - check your internet connection"
        pause
        return 1
    fi

    local branch local_rev remote_rev
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)
    local_rev=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
    remote_rev=$(git -C "$SCRIPT_DIR" rev-parse "origin/$branch" 2>/dev/null || true)

    if [[ -z "$remote_rev" ]]; then
        log_error "Could not find origin/$branch - is this checkout tracking a real branch?"
        pause
        return 1
    fi

    if [[ "$local_rev" == "$remote_rev" ]]; then
        log_success "Already up to date ($branch @ ${local_rev:0:8})"
    else
        echo
        echo "Changes available:"
        git -C "$SCRIPT_DIR" --no-pager log --oneline "${local_rev}..${remote_rev}"
        echo
        if ask_yes_no "Pull these changes and re-apply setup (packages, app files, hardware config)?" "y"; then
            if ! git -C "$SCRIPT_DIR" pull --ff-only origin "$branch"; then
                log_error "Pull failed (not a fast-forward) - resolve manually in $SCRIPT_DIR"
                pause
                return 1
            fi
            log_success "Pulled latest code ($branch @ $(git -C "$SCRIPT_DIR" rev-parse --short HEAD))"

            echo
            log_info "Re-applying setup with the updated code..."
            provision_install_packages
            provision_create_kiosk_user
            provision_install_nodejs

            # Bare call, not `if ! provision_install_app; then`: testing a
            # multi-statement function as an if-condition exempts
            # everything inside it from set -e for the duration (see
            # lib/provision.sh's own call to this same function). $? is
            # captured right after instead - accurate either way, and
            # doesn't add a new exemption on top of the one this action
            # already has from being invoked through run_menu's dispatch.
            provision_install_app
            local app_rc=$?
            if [[ $app_rc -ne 0 ]]; then
                log_error "Upgrade stopped - app reinstall failed, see above"
                pause
                return 1
            fi

            provision_configure_display
            provision_configure_firewall
            provision_configure_power_management
            log_success "Setup refreshed"

            echo
            if ask_yes_no "Restart kiosk display now to apply changes?" "y"; then
                sudo systemctl restart lightdm
            else
                log_info "Restart later with: sudo systemctl restart lightdm"
            fi
        else
            echo "Cancelled"
        fi
    fi

    echo
    if ask_yes_no "Check for and install the latest Electron version too?" "y"; then
        action_update_electron
        return
    fi

    pause
}
