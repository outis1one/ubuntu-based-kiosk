#!/bin/bash
################################################################################
# menus/clone_settings.sh - "Clone Settings" (Advanced): export the portable
# parts of this kiosk's configuration to a JSON file, and apply that file
# to other already-installed kiosks - for standing up several kiosks that
# should share the same sites/settings.
#
# This is deliberately an MVP, not the legacy Export/Import Settings
# redesigned 1:1. It moves only what's actually safe to copy between
# machines automatically:
#   - config.json's portable fields (sites, display/touch, navigation,
#     lockout, password protection) - plain data, no machine binding.
#   - Which addons were present at export time, as an informational
#     checklist on apply - NOT automated installation. That's a
#     deliberately separate, bigger follow-up (each addon would need a
#     non-interactive install variant, mirroring the *_do_uninstall
#     helpers Complete Uninstall already composes).
#
# Explicitly NOT exported, because copying them would be actively wrong,
# not just incomplete:
#   - Authelia credentials: encrypted with a key derived from this
#     machine's /etc/machine-id (addon_authelia.sh) - decrypts to
#     garbage on any other machine.
#   - WireGuard/VPN identity: a private key is that device's identity;
#     reusing one across machines is a peer conflict, not a saving.
#   - Asterisk Intercom's SIP extension: most PBXes reject two
#     simultaneous registrations to the same extension.
# Apply prints all three as an explicit "needs a human" checklist rather
# than silently skipping them.
#
# Depends on: lib/menu.sh, lib/config.sh, and every menus/addon_*.sh
# being sourced first (for the *_is_installed detection helpers).
################################################################################

clone_settings_status() {
    echo "Exports/applies sites, display, navigation, and lockout settings"
    echo "between already-installed kiosks. Addon credentials that are"
    echo "bound to one machine (Authelia, WireGuard, Asterisk Intercom)"
    echo "are never copied - see the checklist after applying a profile."
}

clone_settings_menu_builder() {
    MENU_LABELS=("Export settings" "Apply settings (clone)")
    MENU_HANDLERS=(action_export_clone_settings action_apply_clone_settings)
}

clone_settings_menu() {
    run_menu "CLONE SETTINGS" clone_settings_menu_builder clone_settings_status
}

################################################################################
# Helpers
################################################################################

# JSON array of addon identifiers currently present on this machine.
clone_detect_addons() {
    local addons=()

    cups_is_installed 2>/dev/null && addons+=("cups")
    lms_is_installed 2>/dev/null && addons+=("lms")
    squeezelite_is_installed 2>/dev/null && addons+=("squeezelite")
    is_service_active x11vnc 2>/dev/null && addons+=("vnc")
    command -v wg &>/dev/null && addons+=("wireguard")
    command -v tailscale &>/dev/null && addons+=("tailscale")
    command -v netbird &>/dev/null && addons+=("netbird")
    baresip_is_installed 2>/dev/null && addons+=("asterisk_intercom")

    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        local authelia_url
        authelia_url=$(sudo -u "$KIOSK_USER" jq -r '.autheliaURL // ""' "$CONFIG_PATH" 2>/dev/null || true)
        [[ -n "$authelia_url" ]] && addons+=("authelia")
    fi

    if [[ "${#addons[@]}" -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${addons[@]}" | jq -R . | jq -s . || echo "[]"
    fi
}

################################################################################
# Actions
################################################################################

action_export_clone_settings() {
    echo
    if ! sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        log_error "config.json not found at $CONFIG_PATH - configure sites/settings first"
        pause
        return 1
    fi

    local out_path
    out_path=$(ask_text "Export profile to" "$HOME/kiosk-clone-settings.json")

    local raw_config
    raw_config=$(sudo -u "$KIOSK_USER" cat "$CONFIG_PATH" 2>/dev/null)
    if ! echo "$raw_config" | jq empty 2>/dev/null; then
        log_error "config.json is not valid JSON - cannot export"
        pause
        return 1
    fi

    local settings
    settings=$(echo "$raw_config" | jq 'del(.autheliaURL, .autheliaUsername, .autheliaEncryptedPassword)')

    local addons_present
    addons_present=$(clone_detect_addons)

    jq -n \
        --argjson settings "$settings" \
        --argjson addons "$addons_present" \
        --arg script_version "${SCRIPT_VERSION:-unknown}" \
        '{profile_version: 1, script_version: $script_version, settings: $settings, addons_present: $addons}' \
        > "$out_path"

    log_success "Settings exported to $out_path"
    echo
    echo "Included: sites, display/touch/navigation settings, lockout,"
    echo "password protection (SHA-256 hash only)."
    echo
    echo "NOT included (needs fresh setup on each new device):"
    echo "  - Authelia credentials (encrypted per-machine, won't decrypt elsewhere)"
    echo "  - WireGuard/VPN keys (each device needs its own identity)"
    echo "  - Asterisk Intercom extension (most PBXes reject duplicate registrations)"

    pause
}

action_apply_clone_settings() {
    echo
    local in_path
    in_path=$(ask_text "Profile file to apply" "")
    if [[ -z "$in_path" ]]; then
        echo "Cancelled"
        pause
        return
    fi
    if [[ ! -f "$in_path" ]]; then
        log_error "File not found: $in_path"
        pause
        return 1
    fi
    if ! jq empty "$in_path" 2>/dev/null; then
        log_error "Not valid JSON: $in_path"
        pause
        return 1
    fi

    local settings addons_present
    settings=$(jq -c '.settings // {}' "$in_path" || echo '{}')
    addons_present=$(jq -r '.addons_present[]? // empty' "$in_path" || true)

    echo "Profile summary:"
    echo "  Sites:           $(echo "$settings" | jq '.tabs | length // 0')"
    echo "  Addons expected: $(echo "$addons_present" | tr '\n' ' ')"
    echo
    ask_yes_no "Apply this profile? This overwrites current sites/display/lockout settings." "n" || { echo "Cancelled"; pause; return; }

    sudo mkdir -p "$KIOSK_DIR"
    sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_DIR"

    local existing="{}"
    if sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        existing=$(sudo -u "$KIOSK_USER" cat "$CONFIG_PATH" 2>/dev/null)
        echo "$existing" | jq empty 2>/dev/null || existing="{}"
    fi

    # Merge, not replace - same reasoning as save_config: this machine's
    # own Authelia fields (never in the exported settings blob) must
    # survive an apply untouched. Guarded: $settings came from an
    # external file - a corrupted/hand-edited profile whose "settings"
    # key isn't a JSON object must not be allowed to crash the session.
    local merged
    if ! merged=$(echo "$existing" | jq --argjson s "$settings" '. + $s' 2>/dev/null); then
        log_error "Profile's settings are not a valid JSON object - nothing was changed"
        pause
        return 1
    fi

    local tmp
    tmp=$(mktemp)
    echo "$merged" > "$tmp"
    sudo -u "$KIOSK_USER" bash -c "cat > '$CONFIG_PATH'" < "$tmp"
    sudo -u "$KIOSK_USER" chmod 644 "$CONFIG_PATH"
    rm -f "$tmp"

    log_success "Settings applied"

    echo
    echo "Addon checklist (from the exported profile):"
    local missing_any=false
    if [[ -z "$addons_present" ]]; then
        echo "  (profile recorded no addons)"
    fi
    while IFS= read -r addon; do
        [[ -z "$addon" ]] && continue
        case "$addon" in
            cups)
                if cups_is_installed; then
                    echo "  [x] CUPS Printing - already installed"
                else
                    echo "  [ ] CUPS Printing - not installed, install via Addons"
                    missing_any=true
                fi ;;
            lms)
                if lms_is_installed; then
                    echo "  [x] LMS Server - already installed"
                else
                    echo "  [ ] LMS Server - not installed, install via Addons"
                    missing_any=true
                fi ;;
            squeezelite)
                if squeezelite_is_installed; then
                    echo "  [x] Squeezelite Player - already installed"
                else
                    echo "  [ ] Squeezelite Player - not installed, install via Addons"
                    missing_any=true
                fi ;;
            vnc)
                if is_service_active x11vnc; then
                    echo "  [x] VNC - already installed"
                else
                    echo "  [ ] VNC - not installed, install via Addons"
                    missing_any=true
                fi ;;
            wireguard)
                echo "  [!] WireGuard - needs a NEW keypair/peer on this device, never clone the key" ;;
            tailscale)
                if command -v tailscale &>/dev/null; then
                    echo "  [x] Tailscale - installed (connect with a reusable auth key if not yet connected)"
                else
                    echo "  [ ] Tailscale - not installed, install via Addons"
                    missing_any=true
                fi ;;
            netbird)
                if command -v netbird &>/dev/null; then
                    echo "  [x] Netbird - installed (connect with a reusable setup key if not yet connected)"
                else
                    echo "  [ ] Netbird - not installed, install via Addons"
                    missing_any=true
                fi ;;
            asterisk_intercom)
                echo "  [!] Asterisk Intercom - needs its own SIP extension on this device" ;;
            authelia)
                echo "  [!] Authelia - needs a fresh login on this device" ;;
            *)
                echo "  [?] $addon - unrecognized entry in profile" ;;
        esac
    done <<< "$addons_present"

    if $missing_any; then
        echo
        echo "Install anything marked \"not installed\" above via the Addons menu."
    fi

    pause
}
