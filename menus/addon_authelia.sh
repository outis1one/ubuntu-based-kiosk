#!/bin/bash
################################################################################
# menus/addon_authelia.sh - "Authelia Auto-Login" addon.
#
# Stores encrypted Authelia SSO credentials so the kiosk authenticates
# automatically on every startup. The password is AES-256-CBC encrypted
# with a key derived from this machine's /etc/machine-id via scrypt -
# the encrypted blob is useless on any other machine - and is NEVER
# stored in plain text, matching the legacy addon exactly (same
# algorithm, same salt, same node crypto calls).
#
# autheliaURL/autheliaUsername/autheliaEncryptedPassword are tracked
# fields in lib/config.sh now (load_existing_config/save_config), same
# as every other config.json field this tool manages - this is also
# what motivated fixing save_config to merge onto the existing file
# instead of rebuilding it from scratch (see lib/config.sh): the legacy
# save_config had no idea these three fields existed, so configuring
# Authelia and then visiting Sites/Touch/Navigation/Password Protection
# in the legacy menu would silently wipe the credentials on the next
# save. Real bug in the shipped script, not unique to this migration.
#
# Depends on: lib/menu.sh, lib/config.sh being sourced first.
################################################################################

addon_authelia_status() {
    if [[ -n "$AUTHELIA_URL" ]]; then
        echo "Authelia: configured"
        echo "  URL:      $AUTHELIA_URL"
        echo "  Username: $AUTHELIA_USERNAME"
    else
        echo "Authelia: not configured"
    fi
}

addon_authelia_menu_builder() {
    if [[ -n "$AUTHELIA_URL" ]]; then
        MENU_LABELS=("Reconfigure (overwrite)" "Show server-side setup instructions again" "Clear Authelia configuration")
        MENU_HANDLERS=(action_configure_authelia action_show_authelia_server_setup action_clear_authelia)
    else
        MENU_LABELS=("Configure Authelia auto-login")
        MENU_HANDLERS=(action_configure_authelia)
    fi
}

addon_authelia_menu() {
    load_existing_config

    if ! sudo -u "$KIOSK_USER" test -f "$CONFIG_PATH" 2>/dev/null; then
        log_error "config.json not found at $CONFIG_PATH - run a full install first"
        pause
        return
    fi

    run_menu "AUTHELIA AUTO-LOGIN" addon_authelia_menu_builder addon_authelia_status
}

################################################################################
# Encryption
################################################################################

# Same algorithm as the legacy addon: AES-256-CBC, key derived from
# /etc/machine-id via scrypt with a fixed salt, random IV prepended to
# the ciphertext, everything base64-encoded. main.js decrypts with the
# same derivation - do not change this without updating main.js too.
encrypt_authelia_password() {
    local password="$1"
    command -v node &>/dev/null || return 1

    node -e "
const crypto=require('crypto'),fs=require('fs');
const id=fs.readFileSync('/etc/machine-id','utf8').trim();
const key=crypto.scryptSync(id,'kiosk-authelia-v1',32);
const iv=crypto.randomBytes(16);
const c=crypto.createCipheriv('aes-256-cbc',key,iv);
const enc=Buffer.concat([c.update(process.argv[1],'utf8'),c.final()]);
process.stdout.write(Buffer.concat([iv,enc]).toString('base64'));
" "$password" 2>/dev/null
}

################################################################################
# Actions
################################################################################

action_configure_authelia() {
    echo
    echo "Stores encrypted Authelia credentials so the kiosk"
    echo "authenticates automatically on every startup."
    echo "Password is encrypted with this machine's unique ID -"
    echo "the encrypted blob is useless on any other machine."
    echo

    if [[ -n "$AUTHELIA_URL" ]]; then
        echo "Current config:"
        echo "  URL:      $AUTHELIA_URL"
        echo "  Username: $AUTHELIA_USERNAME"
        echo
        ask_yes_no "Overwrite existing Authelia config?" "n" || { echo "Cancelled"; return; }
        echo
    fi

    local url user pass
    read -r -p "Authelia URL (e.g. https://auth.yourdomain.com): " url
    [[ -z "$url" ]] && { echo "Cancelled"; return; }
    read -r -p "Authelia username: " user
    [[ -z "$user" ]] && { echo "Cancelled"; return; }
    read -r -s -p "Authelia password: " pass
    echo
    [[ -z "$pass" ]] && { echo "Cancelled"; return; }

    echo "Encrypting with machine ID..."
    local encrypted
    encrypted=$(encrypt_authelia_password "$pass")
    if [[ -z "$encrypted" ]]; then
        log_error "Encryption failed - is Node.js installed?"
        return 1
    fi

    AUTHELIA_URL="$url"
    AUTHELIA_USERNAME="$user"
    AUTHELIA_ENCRYPTED_PASSWORD="$encrypted"
    save_config

    log_success "Authelia config saved (password encrypted, NOT stored in plain text)"
    action_show_authelia_server_setup

    echo
    if is_service_active lightdm && ask_yes_no "Restart kiosk display now?" "n"; then
        sudo systemctl restart lightdm
    fi
}

action_clear_authelia() {
    echo
    ask_yes_no "Clear Authelia configuration?" "n" || { echo "Cancelled"; return; }

    AUTHELIA_URL=""
    AUTHELIA_USERNAME=""
    AUTHELIA_ENCRYPTED_PASSWORD=""
    save_config
    log_success "Authelia configuration cleared"
}

action_show_authelia_server_setup() {
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "       AUTHELIA SERVER-SIDE SETUP (Dockerized)"
    echo "════════════════════════════════════════════════════════════"
    echo
    echo "1. Generate the argon2 password hash on your Docker host:"
    echo
    echo "   docker run --rm authelia/authelia:latest \\"
    echo "     authelia crypto hash generate argon2 \\"
    echo "     --password 'yourpassword'"
    echo
    echo "   Copy the \$argon2id\$... output — that is your hash."
    echo
    echo "2. ADD a kiosk user to ~/docker/authelia/config/users.yml"
    echo "   (append — do not replace existing users):"
    echo
    echo "   kiosk:"
    echo "     displayname: \"Kiosk Display\""
    echo "     password: '\$argon2id\$v=19\$m=65536,t=3,p=4\$<paste hash here>'"
    echo "     email: kiosk@local.com"
    echo "     groups:"
    echo "       - kiosk"
    echo
    echo "3. MERGE into ~/docker/authelia/config/configuration.yml:"
    echo
    echo "   ── access_control ─────────────────────────────────────"
    echo "   Find your EXISTING access_control block and add the"
    echo "   kiosk rule as the FIRST rule inside it."
    echo
    echo "   !! DO NOT create a second access_control: block !!"
    echo "   YAML silently ignores duplicate keys — the kiosk rule"
    echo "   will be invisible to Authelia and you will get a white"
    echo "   screen on the kiosk."
    echo
    echo "   Authelia reads rules top-down, first match wins."
    echo "   The kiosk rule MUST be above any two_factor rule or"
    echo "   the two_factor wildcard will match first."
    echo
    echo "   ── EXAMPLE — before (your existing config): ──────────"
    echo "   access_control:"
    echo "     default_policy: deny"
    echo "     rules:"
    echo "       - domain: '*.yourdomain.com'"
    echo "         policy: two_factor"
    echo
    echo "   ── EXAMPLE — after (add kiosk rule above two_factor): ─"
    echo "   access_control:"
    echo "     default_policy: deny"
    echo "     rules:"
    echo "       - domain: '*.yourdomain.com'       # <-- kiosk first"
    echo "         subject: 'group:kiosk'"
    echo "         policy: one_factor"
    echo "       - domain: '*.yourdomain.com'       # <-- existing"
    echo "         policy: two_factor"
    echo
    echo "   Why one_factor? The kiosk authenticates via the API"
    echo "   (/api/firstfactor — password only). TOTP and WebAuthn"
    echo "   require a second interactive step that is impossible"
    echo "   from a script, so the kiosk group must use one_factor."
    echo
    echo "   ── session ─────────────────────────────────────────────"
    echo "   Keep your existing session block — no changes needed."
    echo "   The kiosk re-authenticates via API on every startup so"
    echo "   session expiry barely matters for it."
    echo
    echo "   If you do NOT yet have a session block, add:"
    echo
    echo "   session:"
    echo "     expiration: 8h"
    echo "     inactivity: 1h"
    echo "     remember_me: 7d"
    echo "     cookies:"
    echo "       - domain: yourdomain.com"
    echo "         authelia_url: https://auth.yourdomain.com"
    echo
    echo "4. Restart Authelia on your Docker host:"
    echo "   docker compose restart authelia"
    echo
    echo "────────────────────────────────────────────────────────────"
    echo "  NOTE: HTTP Basic Auth (per-site username/password) still"
    echo "  works alongside Authelia for sites that use browser-popup"
    echo "  authentication rather than Authelia SSO."
    echo "────────────────────────────────────────────────────────────"
    echo
    echo "  To clear Authelia config later, use this menu's"
    echo "  'Clear Authelia configuration' option."
    echo
    pause
}
