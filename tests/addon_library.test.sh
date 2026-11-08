#!/bin/bash
################################################################################
# tests/addon_library.test.sh - tests for menus/addon_library.sh + lib/docker.sh
#
# Runs entirely in a scratch directory with a stub `sudo`, a stub `docker` and
# a fixture stack standing in for library/, so it needs no root, no Docker and
# no network - and cannot touch a real kiosk. (The real stack is exercised by
# library/install.sh itself.)
#
#   bash tests/addon_library.test.sh
################################################################################
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; }
check() { # check "description" command...
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}

# ---- stubs --------------------------------------------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/sudo" << 'EOF'
#!/bin/bash
# Stub sudo: drop "-u USER" and run the command as-is.
if [[ "$1" == "-u" ]]; then shift 2; fi
exec "$@"
EOF
cat > "$T/bin/docker" << 'EOF'
#!/bin/bash
# Stub docker: logs every call; container state comes from $STUB_STATE.
echo "$*" >> "$STUB_LOG"
case "$1" in
  --version) echo "Docker version 99.0.0, build stub"; exit 0 ;;
  info) exit 0 ;;
  compose)
    [[ "$2" == "version" ]] && { echo "Docker Compose version v9"; exit 0; }
    exit 0 ;;
  inspect)
    st="$(cat "$STUB_STATE" 2>/dev/null || echo missing)"
    [[ "$st" == "missing" ]] && exit 1
    case "$*" in *Health*) echo healthy ;; *) echo "$st" ;; esac
    exit 0 ;;
esac
exit 0
EOF
chmod +x "$T/bin/sudo" "$T/bin/docker"
export PATH="$T/bin:$PATH"
export STUB_LOG="$T/docker.log" STUB_STATE="$T/state"
echo missing > "$STUB_STATE"; : > "$STUB_LOG"

# ---- fixture "checkout" with a stub library stack ----------------------------
FIX="$T/checkout"
mkdir -p "$FIX/library/koha/certs"
echo "name: library" > "$FIX/library/docker-compose.yml"
echo "SHOULD-NOT-BE-COPIED" > "$FIX/library/.env"
echo "cert" > "$FIX/library/koha/certs/proxy.crt"
echo "koha-file" > "$FIX/library/koha/Dockerfile"
cat > "$FIX/library/install.sh" << 'EOF'
#!/bin/bash
# Stub of library/install.sh: records how it was called and writes a .env.
HERE="$(cd "$(dirname "$0")" && pwd)"
echo "install.sh $* LIBRARY_NAME=${LIBRARY_NAME:-} BIND_ADDR=${BIND_ADDR:-}" >> "$STUB_LOG"
[[ "${1:-}" == "--update" ]] && exit 0
cat > "$HERE/.env" << ENV
LIBRARY_NAME="${LIBRARY_NAME:-}"
OPAC_PORT=8080
STAFF_PORT=8081
QUICKADD_PORT=8082
ADMIN_USER=admin
ADMIN_PASSWORD=s3cretPASS
VIEWER_USER=guest
VIEWER_PASSWORD=guestPASS
BIND_ADDR=${BIND_ADDR:-0.0.0.0}
ENV
echo running > "$STUB_STATE"
EOF

# ---- environment the addon expects -------------------------------------------
export KIOSK_USER="$(id -un)"
export KIOSK_HOME="$T/home" KIOSK_DIR="$T/home/kiosk-app" CONFIG_PATH="$T/home/kiosk-app/config.json"
export LIBRARY_DIR="$T/opt-library"
SCRIPT_DIR="$FIX"
mkdir -p "$KIOSK_DIR"
cat > "$CONFIG_PATH" << 'EOF'
{"tabs":[{"url":"https://example.com","duration":60,"username":"","password":"","name":"Example"}],
 "homeTabIndex":-1,"inactivityTimeout":120,"swipeMode":"dual","allowNavigation":"same-origin","somethingUntracked":"keep-me"}
EOF

# shellcheck disable=SC1090
source "$REPO/lib/menu.sh"
source "$REPO/lib/config.sh"
source "$REPO/lib/docker.sh"
source "$REPO/menus/addon_library.sh"
export KIOSK_UNATTENDED=0
docker_ensure_installed() { return 0; }   # the stub stands in for a working Docker

tabs() { jq -r '.tabs[] | "\(.url)|\(.duration)|\(.name)|\(.username)"' "$CONFIG_PATH"; }

# ============================================================================
echo "== lib/docker.sh"
check "docker_is_installed sees the stub"      docker_is_installed
check "container state: missing"               test "$(docker_container_state library-koha)" = missing
echo running > "$STUB_STATE"
check "container state: running"               test "$(docker_container_state library-koha)" = running
check "container health: healthy"              test "$(docker_container_health library-koha)" = healthy
echo missing > "$STUB_STATE"
check "docker_free_port returns a number"      test -n "$(docker_free_port 20000)"

# ============================================================================
echo "== sync files"
mkdir -p "$LIBRARY_DIR"; echo "DEPLOYED-ENV" > "$LIBRARY_DIR/.env"
library_sync_files
check "copies the stack files"                 test -f "$LIBRARY_DIR/koha/Dockerfile"
check "never overwrites a deployed .env"       test "$(cat "$LIBRARY_DIR/.env")" = DEPLOYED-ENV
check "does not copy certificates"             test ! -e "$LIBRARY_DIR/koha/certs/proxy.crt"
rm -rf "$LIBRARY_DIR"

# ============================================================================
echo "== not installed"
if library_is_installed; then bad "library_is_installed false before install"; else ok "library_is_installed false before install"; fi
addon_library_menu_builder
check "offers only Install"                    test "${MENU_LABELS[*]}" = "Install Library Catalog"
check "status says not installed"              test "$(addon_library_status)" = "Library Catalog: not installed"

# ============================================================================
echo "== install action (kiosk-only network, show on kiosk)"
# answers: library name, allow-network=n, show-on-kiosk=y, <Enter> for pause
printf 'Smith Family Library\nn\ny\n\n' | action_library_install >"$T/install.out" 2>&1
check "install.sh got the library name"        grep -q 'LIBRARY_NAME=Smith Family Library' "$STUB_LOG"
check "install.sh got BIND_ADDR=127.0.0.1"     grep -q 'BIND_ADDR=127.0.0.1' "$STUB_LOG"
check "is_installed is now true"               library_is_installed
check "Find a book tab added, duration 0"      grep -qx 'http://localhost:8081/add/#find|0|Find a book|guest' <(tabs)
check "tab carries the read-only guest password" test "$(jq -r '.tabs[] | select(.name=="Find a book") | .password' "$CONFIG_PATH")" = guestPASS
check "admin password never goes in kiosk config" bash -c "! grep -q s3cretPASS '$CONFIG_PATH'"
check "existing tab preserved"                 grep -qx 'https://example.com|60|Example|' <(tabs)
check "untracked config keys preserved"        test "$(jq -r .somethingUntracked "$CONFIG_PATH")" = keep-me
addon_library_status > "$T/status.out"
check "status shows 'this kiosk only'"         grep -q 'this kiosk only' "$T/status.out"

# ============================================================================
echo "== menu while installed"
addon_library_menu_builder
check "offers 'stop showing' (tab exists)"     grep -q 'Stop showing Find a book' <<< "${MENU_LABELS[*]}"
check "has Update and Uninstall"               grep -q 'Update.*Uninstall' <<< "${MENU_LABELS[*]}"

echo "== tab toggling is idempotent"
library_add_tab >/dev/null 2>&1
check "adding again does not duplicate"        test "$(tabs | grep -c 'localhost:8081/add/#find')" = 1
printf '\n' | action_library_toggle_tab >/dev/null 2>&1    # now removes it
check "toggle removes the Find a book tab"       test "$(tabs | grep -c 'localhost:8081/add/#find')" = 0
check "toggle keeps the other tab"             grep -qx 'https://example.com|60|Example|' <(tabs)
addon_library_menu_builder
check "menu now offers 'Show'"                 grep -q 'Show Find a book on the kiosk' <<< "${MENU_LABELS[*]}"
printf '\n' | action_library_toggle_tab >/dev/null 2>&1    # and adds it back
check "toggle adds it back"                    test "$(tabs | grep -c 'localhost:8081/add/#find')" = 1

# ============================================================================
echo "== an earlier version's tab (public catalogue address) is cleaned up"
jq '.tabs += [{"url":"http://localhost:8080/","duration":0,"username":"","password":"","name":"Library catalogue"}]' "$CONFIG_PATH" > "$T/cfg.tmp" && cp "$T/cfg.tmp" "$CONFIG_PATH"
check "old catalogue tab present before"       test "$(tabs | grep -c '^http://localhost:8080/|')" = 1
library_remove_tab >/dev/null 2>&1
check "old catalogue tab removed"              test "$(tabs | grep -c '^http://localhost:8080/|')" = 0
check "other tabs untouched"                   grep -qx 'https://example.com|60|Example|' <(tabs)
library_add_tab >/dev/null 2>&1

echo "== network access"
: > "$STUB_LOG"
printf 'y\n\n' | action_library_network >/dev/null 2>&1       # allow network
check ".env BIND_ADDR is now 0.0.0.0"          test "$(library_env_get BIND_ADDR)" = 0.0.0.0
check "containers were recreated"              grep -q 'compose --project-directory .* up -d' "$STUB_LOG"
printf 'n\n\n' | action_library_network >/dev/null 2>&1       # back to kiosk-only
check ".env BIND_ADDR back to 127.0.0.1"       test "$(library_env_get BIND_ADDR)" = 127.0.0.1

# ============================================================================
echo "== access screen"
printf '\n' | action_library_show_access > "$T/access.out" 2>&1
check "shows the admin login"                  grep -q 'admin  /  s3cretPASS' "$T/access.out"
check "shows the read-only login to share"     grep -q 'guest  /  guestPASS' "$T/access.out"
check "shows the one library address"          grep -q 'sign in here.*:8081/' "$T/access.out"
check "shows the one address (no /add/ path)" grep -q ':8081/ ' "$T/access.out"

# ============================================================================
echo "== update"
: > "$STUB_LOG"
printf 'y\n\n' | action_library_update >/dev/null 2>&1
check "runs install.sh --update"               grep -q 'install.sh --update' "$STUB_LOG"
check "update keeps the .env"                  test "$(library_env_get ADMIN_PASSWORD)" = s3cretPASS

# ============================================================================
echo "== uninstall keeps the books by default"
: > "$STUB_LOG"
printf 'n\n\n' | action_library_uninstall >/dev/null 2>&1
check "compose down without -v"                grep -qE 'compose .* down$' "$STUB_LOG"
check "no volume deletion"                     bash -c "! grep -q -- ' -v' '$STUB_LOG'"
check "install dir and .env kept"              test -f "$LIBRARY_DIR/.env"
check "catalogue tab removed"                  test "$(tabs | grep -c 'localhost:8081/add/#find')" = 0

echo "== purge needs the typed confirmation"
printf 'y\nnope\n\n' | action_library_uninstall >/dev/null 2>&1
check "wrong confirmation cancels"             test -f "$LIBRARY_DIR/.env"
: > "$STUB_LOG"
library_add_tab >/dev/null 2>&1
printf 'y\nDELETE\n\n' | action_library_uninstall >/dev/null 2>&1
check "compose down -v --rmi local"            grep -q 'down -v --rmi local' "$STUB_LOG"
check "install dir removed"                    test ! -e "$LIBRARY_DIR"
check "tab removed again"                      test "$(tabs | grep -c 'localhost:8081/add/#find')" = 0
check "other tab still there"                  grep -qx 'https://example.com|60|Example|' <(tabs)

echo
echo "passed: $PASS   failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
