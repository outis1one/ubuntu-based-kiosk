#!/bin/bash
# One-command setup for a self-hosted home library (Koha) on Ubuntu/Debian.
#
#   sudo ./install.sh                 # install Docker if needed, build, start
#   sudo ./install.sh --status        # show URLs and container health
#   sudo ./install.sh --update        # rebuild with the latest Koha and restart
#   sudo ./install.sh --stop | --start
#
# Optional environment variables:
#   LIBRARY_NAME="Smith Family Library"   name shown on the catalogue
#   LIBRARY_CODE=HOME                     short code for the library (letters/digits)
#   SHELVES="LR=Living room;BR=Bedroom"   shelves/rooms to offer (first install only)
#   ITEM_TYPES="CD=Compact disc"          extra item types (first install only)
#   OPAC_PORT=8080 STAFF_PORT=8081        preferred host ports (next free is used)
#   EXTRA_CA=/path/to/proxy-ca.crt        trust an extra CA while building
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

c_info()  { printf '\033[0;34m[INFO]\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[0;32m[ OK ]\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
c_err()   { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*" >&2; }

[ "$(id -u)" = 0 ] || { c_err "Run with sudo:  sudo $0 $*"; exit 1; }
RUN_USER="${SUDO_USER:-root}"

# --- Docker -------------------------------------------------------------------
ensure_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        c_ok "Docker $(docker --version | awk '{print $3}' | tr -d ,) with Compose is installed"
    else
        c_info "Installing Docker (official get.docker.com script)..."
        command -v curl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq curl ca-certificates; }
        curl -fsSL https://get.docker.com | sh
        docker compose version >/dev/null 2>&1 || apt-get install -y -qq docker-compose-plugin
        c_ok "Docker installed"
    fi
    systemctl enable --now docker >/dev/null 2>&1 || true
    if [ "$RUN_USER" != root ] && ! id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx docker; then
        usermod -aG docker "$RUN_USER" && c_info "Added $RUN_USER to the docker group (log out/in to use docker without sudo)"
    fi
    docker info >/dev/null 2>&1 || { c_err "The Docker daemon is not running."; exit 1; }
}

port_in_use() {
    if command -v ss >/dev/null 2>&1; then
        ss -tlnH "sport = :$1" 2>/dev/null | grep -q .
    else                                   # minimal systems without iproute2
        (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
    fi
}
free_port()   { local p="$1"; while port_in_use "$p"; do p=$((p + 1)); done; echo "$p"; }
rand()        { head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
lan_ip()      { hostname -I 2>/dev/null | awk '{print $1}'; }

dc() { docker compose --project-directory "$HERE" "$@"; }

# Docker Hub rate-limits anonymous pulls (HTTP 429), which is common on shared
# IPs; retry with a growing pause instead of failing the whole install.
with_retry() {
    local n=1 max=5 wait=15
    until "$@"; do
        [ "$n" -ge "$max" ] && { c_err "Failed after $max attempts: $*"; return 1; }
        c_warn "Attempt $n failed (Docker Hub rate limit or network?) - retrying in ${wait}s..."
        sleep "$wait"; n=$((n + 1)); wait=$((wait * 2))
    done
}

show_status() {
    [ -f .env ] || { c_err "Not installed yet - run: sudo ./install.sh"; exit 1; }
    # shellcheck disable=SC1091
    . ./.env
    local ip; ip="$(lan_ip)"; ip="${ip:-localhost}"
    if [ "${BIND_ADDR:-0.0.0.0}" = "127.0.0.1" ]; then
        ip="localhost"
        echo "  (Limited to this machine: BIND_ADDR=127.0.0.1 in .env)"
    fi
    dc ps
    echo
    echo "  Your library:        http://$ip:$STAFF_PORT"
    echo "      sign in here: find a book, add books (scan an ISBN or use the phone camera), lending, labels, people"
    echo "  Admin login:         $ADMIN_USER  /  $ADMIN_PASSWORD   (also stored in $HERE/.env)"
    echo "  Read-only login:     ${VIEWER_USER:-guest}  /  ${VIEWER_PASSWORD:-?}   (to hand out, with this address: http://$ip:$STAFF_PORT/add/)"
    echo "      It opens the Find a book page: search only, it cannot add or change anything."
    if [ "${OPAC_BIND:-127.0.0.1}" != "127.0.0.1" ]; then
        echo "  Public catalogue:    http://$ip:$OPAC_PORT   (search only, asks for a library card login)"
    fi
    echo
}

case "${1:-}" in
    --status) show_status; exit 0 ;;
    --stop)   dc stop; exit 0 ;;
    --start)  dc start; exit 0 ;;
    --update)
        ensure_docker
        with_retry dc build --pull --no-cache koha
        dc up -d
        show_status; exit 0 ;;
    "" ) ;;
    *) c_err "Unknown option: $1"; exit 1 ;;
esac

ensure_docker

# --- Settings (.env is created once and never overwritten) ------------------------
if [ ! -f .env ]; then
    c_info "Generating settings and passwords..."
    TZ_NOW="$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"
    umask 077
    cat > .env << ENVEOF
# Generated by install.sh - keep this file private.
LIBRARY_NAME="${LIBRARY_NAME:-My Library}"
LIBRARY_CODE=${LIBRARY_CODE:-HOME}
SHELVES="${SHELVES:-}"
ITEM_TYPES="${ITEM_TYPES:-}"
TZ=${TZ_NOW}
OPAC_PORT=$(free_port "${OPAC_PORT:-8080}")
STAFF_PORT=$(free_port "${STAFF_PORT:-8081}")
QUICKADD_PORT=$(free_port "${QUICKADD_PORT:-8082}")
BIND_ADDR=${BIND_ADDR:-0.0.0.0}
# The public catalogue is off by default: 127.0.0.1 = not reachable from the network.
OPAC_BIND=${OPAC_BIND:-127.0.0.1}
ADMIN_USER=admin
ADMIN_PASSWORD=$(rand 16)
VIEWER_USER=guest
VIEWER_PASSWORD=$(rand 14)
DB_ROOT_PASSWORD=$(rand 32)
DB_PASSWORD=$(rand 32)
KOHA_SUITE=stable
ENVEOF
    umask 022
    [ "$RUN_USER" = root ] || chown "$RUN_USER" .env
else
    c_info "Re-using existing .env"
    # Settings added in later versions: append them to an older .env.
    if ! grep -q '^QUICKADD_PORT=' .env; then
        echo "QUICKADD_PORT=$(free_port 8082)" >> .env
    fi
    if ! grep -q '^VIEWER_PASSWORD=' .env; then
        { echo "VIEWER_USER=guest"; echo "VIEWER_PASSWORD=$(rand 14)"; } >> .env
    fi
    # Existing installs keep their current public-catalogue behaviour.
    grep -q '^OPAC_BIND=' .env || echo "OPAC_BIND=0.0.0.0" >> .env
    if ! grep -q '^BIND_ADDR=' .env; then
        echo "BIND_ADDR=${BIND_ADDR:-0.0.0.0}" >> .env
    fi
fi

if [ -n "${EXTRA_CA:-}" ]; then
    cp "$EXTRA_CA" koha/certs/extra-ca.crt
    cp "$EXTRA_CA" quickadd/certs/extra-ca.crt
    c_info "Trusting extra CA during the build: $EXTRA_CA"
fi

# --- Build and start ---------------------------------------------------------------
c_info "Building the Koha image (first time: 5-10 minutes, downloads ~1 GB)..."
with_retry dc build
c_info "Starting..."
with_retry dc up -d

# --- Wait until the site answers ---------------------------------------------------
# shellcheck disable=SC1091
. ./.env
c_info "First start installs the database - waiting until Koha reports healthy..."
for i in $(seq 1 180); do
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' library-koha 2>/dev/null || echo missing)"
    if [ "$health" = healthy ] && curl -fsS -o /dev/null -m 5 "http://127.0.0.1:${QUICKADD_PORT:-8082}/healthz" 2>/dev/null; then READY=1; break; fi
    # One restart is tolerated (Docker's restart policy); a crash loop is not.
    if [ "$(docker inspect -f '{{.RestartCount}}' library-koha 2>/dev/null || echo 99)" -ge 3 ]; then
        c_err "library-koha keeps crashing - see: docker logs library-koha"; exit 1
    fi
    sleep 5
done
[ "${READY:-0}" = 1 ] || { c_err "Timed out - see: docker logs -f library-koha"; exit 1; }

c_ok "Your library is running."
echo
show_status
