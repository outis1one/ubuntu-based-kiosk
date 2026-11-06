#!/bin/bash
################################################################################
# lib/docker.sh - Docker / Compose tooling shared by every addon that runs a
# containerised service (the Library Catalog addon is the first).
#
# Everything here goes through `sudo docker ...`: the kiosk admin runs
# install.sh as a regular user and is deliberately NOT put in the `docker`
# group (docker-group membership is root-equivalent).
#
# Depends on: lib/menu.sh (log_* helpers) being sourced first.
################################################################################

# Overridable so tests can substitute stubs for the real binaries.
: "${DOCKER_BIN:=docker}"

docker_is_installed() {
    command -v "$DOCKER_BIN" >/dev/null 2>&1 \
        && sudo "$DOCKER_BIN" compose version >/dev/null 2>&1
}

docker_daemon_running() {
    sudo "$DOCKER_BIN" info >/dev/null 2>&1
}

# Install Docker Engine + the Compose plugin if they are missing.
#
# Ubuntu 24.04+ ships both in its own archive (docker.io, docker-compose-v2):
# preferred because it also works through the offline apt bundle's mirror and
# gets security updates with everything else. On releases without
# docker-compose-v2 (22.04), fall back to Docker's official install script.
docker_ensure_installed() {
    if docker_is_installed; then
        docker_daemon_running || sudo systemctl enable --now docker >/dev/null 2>&1 || true
        log_success "Docker $(sudo "$DOCKER_BIN" --version 2>/dev/null | awk '{print $3}' | tr -d ,) is installed"
        return 0
    fi

    log_info "Installing Docker..."
    if ! sudo apt-get update -qq; then
        log_error "apt update failed - check the network/package sources and try again"
        return 1
    fi
    if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 \
            || { log_error "Installing docker.io / docker-compose-v2 failed"; return 1; }
    else
        log_info "This Ubuntu release has no docker-compose-v2 package - using Docker's install script"
        have_internet 2>/dev/null || { log_error "No internet connection - can't download Docker"; return 1; }
        local script
        script=$(mktemp)
        if ! curl -fsSL https://get.docker.com -o "$script"; then
            rm -f "$script"
            log_error "Could not download Docker's install script"
            return 1
        fi
        sudo sh "$script" || { rm -f "$script"; log_error "Docker's install script failed"; return 1; }
        rm -f "$script"
    fi

    sudo systemctl enable --now docker >/dev/null 2>&1 || true
    if ! docker_is_installed || ! docker_daemon_running; then
        log_error "Docker was installed but is not working - check: sudo systemctl status docker"
        return 1
    fi
    log_success "Docker installed"
}

# docker_compose DIR args...   -> sudo docker compose --project-directory DIR args...
docker_compose() {
    local dir="$1"; shift
    sudo "$DOCKER_BIN" compose --project-directory "$dir" "$@"
}

# docker_container_state NAME -> running | exited | restarting | ... | missing
docker_container_state() {
    sudo "$DOCKER_BIN" inspect -f '{{.State.Status}}' "$1" 2>/dev/null || echo "missing"
}

# docker_container_health NAME -> healthy | unhealthy | starting | none | missing
docker_container_health() {
    sudo "$DOCKER_BIN" inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null \
        || echo "missing"
}

# docker_wait_http URL [TIMEOUT_SECONDS]
# Polls until URL answers 2xx/3xx; returns 1 on timeout.
docker_wait_http() {
    local url="$1" timeout="${2:-300}" waited=0
    while (( waited < timeout )); do
        if curl -fsS -o /dev/null -m 5 "$url" 2>/dev/null; then
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    return 1
}

# docker_free_port START -> prints the first TCP port >= START nothing listens on.
docker_free_port() {
    local port="$1"
    while ss -tlnH "sport = :${port}" 2>/dev/null | grep -q .; do
        port=$((port + 1))
    done
    echo "$port"
}
