#!/bin/bash
################################################################################
# iso/offline/build-bundle.sh - Build the offline install bundle that
# `iso/build-iso.sh --offline` puts on the ISO, so a kiosk can be installed
# with no internet at all. Called by build-iso.sh; not normally run by hand.
#
# Usage: build-bundle.sh OUT_DIR SOURCE_ISO REPO_DIR CACHE_DIR
#
# OUT_DIR ends up as /opt/kiosk-offline on the installed system:
#   apt/              Local apt repository (flat, [trusted=yes]) with every
#                     package install.sh's provisioning and the CUPS addon
#                     install ask for, NodeSource's nodejs, and all their
#                     dependencies that a fresh Ubuntu Server install from
#                     SOURCE_ISO doesn't already have.
#   npm/kiosk-app-node_modules.tar.gz   Prebuilt node_modules (Electron
#   npm/webui-node_modules.tar.gz       included) in place of `npm install`.
#   bundle-info.txt   What was bundled, from where, when.
#
# Package lists are read from REPO_DIR's own lib/provision.sh and
# menus/addon_cups.sh (PROVISION_APT_PACKAGES, PROVISION_INTEL_APT_PACKAGES,
# CUPS_APT_PACKAGES), so the bundle always matches what install.sh asks for.
#
# Dependencies are resolved against SOURCE_ISO's own package manifest - a
# fake dpkg status built from it (fake-dpkg-status.py) - so apt only
# downloads what's actually missing and makes the same choices (virtual
# packages, alternatives) it will make on the real target.
#
# CACHE_DIR keeps apt's downloaded .debs, npm's cache and Electron's
# download between builds, so a rebuild only fetches what changed.
#
# Build host: Ubuntu or Debian, amd64 (Node.js from the bundled .deb is
# run here to build node_modules). Needs: apt-get, apt-ftparchive
# (apt-utils), dpkg-deb, python3, gpg, curl, xorriso, and
# /usr/share/keyrings/ubuntu-archive-keyring.gpg (ubuntu-keyring).
################################################################################

set -euo pipefail

OUT_DIR="$1"
SRC_ISO="$2"
REPO_DIR="$3"
CACHE_DIR="$4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UBUNTU_MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
NODESOURCE_REPO="https://deb.nodesource.com/node_22.x"
NODESOURCE_KEY="https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key"
UBUNTU_KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg

# Needed on the target beyond install.sh's own lists: kiosk-firstboot's
# prerequisites, wget (lib/electron.sh's fallback), and openssh-server
# (installed by the Ubuntu installer only when it had a network).
EXTRA_APT_PACKAGES=(nodejs jq git curl wget unzip openssh-server)

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "    $*"; }

for cmd in apt-get apt-ftparchive dpkg-deb dpkg python3 gpg curl xorriso tar gzip; do
    command -v "$cmd" &>/dev/null \
        || die "--offline needs '$cmd' - on Ubuntu/Debian: sudo apt install apt-utils dpkg python3 gnupg curl xorriso"
done
[[ "$(dpkg --print-architecture)" == "amd64" ]] \
    || die "--offline must be built on an amd64 machine (it runs the bundled Node.js to build node_modules)"
[[ -r "$UBUNTU_KEYRING" ]] \
    || die "missing $UBUNTU_KEYRING - install it: sudo apt install ubuntu-keyring"

rm -rf "$OUT_DIR/apt" "$OUT_DIR/npm"
mkdir -p "$OUT_DIR/apt" "$OUT_DIR/npm" "$CACHE_DIR"
# apt's Dir= and Signed-By need absolute paths.
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
REPO_DIR="$(cd "$REPO_DIR" && pwd)"
SRC_ISO="$(cd "$(dirname "$SRC_ISO")" && pwd)/$(basename "$SRC_ISO")"

################################################################################
# Which Ubuntu release, and what a default server install already has
################################################################################

codename="$(xorriso -indev "$SRC_ISO" -ls /dists 2>/dev/null \
    | tr -d "'" | awk '{print $NF}' | grep -E '^[a-z]+$' | head -1)"
[[ -n "$codename" ]] || die "couldn't tell the Ubuntu release of $SRC_ISO (no /dists on it)"

manifest="$CACHE_DIR/server.manifest"
xorriso -osirrox on -indev "$SRC_ISO" \
    -extract /casper/ubuntu-server-minimal.ubuntu-server.manifest.full "$manifest" 2>/dev/null \
    || die "no server package manifest on $SRC_ISO (casper/ubuntu-server-minimal.ubuntu-server.manifest.full)"
chmod u+w "$manifest"

################################################################################
# Standalone apt environment for $codename (never touches the host's apt)
################################################################################

R="$CACHE_DIR/aptroot-$codename"
mkdir -p "$R/etc/apt/apt.conf.d" "$R/etc/apt/preferences.d" "$R/etc/apt/sources.list.d" \
    "$R/var/lib/apt/lists/partial" "$R/var/cache/apt/archives/partial" "$R/var/lib/dpkg" "$R/keys"
: > "$R/etc/apt/sources.list"
cp "$UBUNTU_KEYRING" "$R/keys/ubuntu.gpg"
curl -fsSL "$NODESOURCE_KEY" | gpg --dearmor --yes -o "$R/keys/nodesource.gpg"
cat > "$R/etc/apt/sources.list.d/bundle.sources" <<EOF
Types: deb
URIs: $UBUNTU_MIRROR
Suites: $codename $codename-updates $codename-security
Components: main restricted universe multiverse
Signed-By: $R/keys/ubuntu.gpg

Types: deb
URIs: $NODESOURCE_REPO
Suites: nodistro
Components: main
Signed-By: $R/keys/nodesource.gpg
EOF

APT=(apt-get
    -o "Dir=$R" -o "Dir::State::status=$R/var/lib/dpkg/status"
    -o APT::Architecture=amd64 -o APT::Architectures::=amd64
    -o Acquire::Languages=none -o Acquire::GzipIndexes=false
    -o Debug::NoLocking=1 -q)

info "Fetching $codename package indexes..."
: > "$R/var/lib/dpkg/status"
"${APT[@]}" update >/dev/null
python3 "$HERE/fake-dpkg-status.py" "$manifest" "$R/var/lib/apt/lists" > "$R/var/lib/dpkg/status"
"${APT[@]}" check >/dev/null || die "baseline from the ISO manifest is inconsistent"

################################################################################
# Packages
################################################################################

# shellcheck disable=SC1091,SC2034
mapfile -t packages < <(
    SCRIPT_DIR="$REPO_DIR"
    source "$REPO_DIR/lib/provision.sh"
    source "$REPO_DIR/menus/addon_cups.sh"
    printf '%s\n' "${PROVISION_APT_PACKAGES[@]}" "${PROVISION_INTEL_APT_PACKAGES[@]}" \
        "${CUPS_APT_PACKAGES[@]}" "${EXTRA_APT_PACKAGES[@]}"
)
(( ${#packages[@]} > 20 )) || die "couldn't read the package lists from $REPO_DIR"

info "Resolving ${#packages[@]} packages (with recommends, as install.sh installs them)..."
# --print-uris against an empty archive dir: it leaves out anything already
# in the cache, which on a rebuild would be everything.
rm -rf "$R/empty-archives"; mkdir -p "$R/empty-archives/partial"
mapfile -t debs < <("${APT[@]}" -qq -o "Dir::Cache::archives=$R/empty-archives" \
    install --print-uris -y "${packages[@]}" | awk '{print $2}')
(( ${#debs[@]} )) || die "apt resolved nothing to download - check the output above"

info "Downloading ${#debs[@]} .debs (cached between builds)..."
"${APT[@]}" install --download-only -y "${packages[@]}" >/dev/null

for f in "${debs[@]}"; do
    cp "$R/var/cache/apt/archives/$f" "$OUT_DIR/apt/"
done
(
    cd "$OUT_DIR/apt"
    apt-ftparchive packages . > Packages 2>/dev/null
    gzip -9 -k Packages
    apt-ftparchive release . > Release
)

################################################################################
# node_modules, built with the exact Node.js being bundled
################################################################################

node_deb="$(printf '%s\n' "${debs[@]}" | grep -E '^nodejs_' | head -1 || true)"
[[ -n "$node_deb" ]] || node_deb="$(cd "$R/var/cache/apt/archives" && ls nodejs_*_amd64.deb 2>/dev/null | sort -V | tail -1)"
[[ -n "$node_deb" ]] || die "no nodejs .deb downloaded"
node_root="$CACHE_DIR/node-root"
rm -rf "$node_root"
dpkg-deb -x "$R/var/cache/apt/archives/$node_deb" "$node_root"
export PATH="$node_root/usr/bin:$PATH"
export npm_config_cache="$CACHE_DIR/npm-cache"
export electron_config_cache="$CACHE_DIR/electron-cache"
export npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
info "Building node_modules with Node.js $(node -v)..."

# build_modules NAME SRC_DIR NPM_ARGS...
build_modules() {
    local name="$1" src="$2"; shift 2
    local tmp="$CACHE_DIR/build-$name"
    rm -rf "$tmp"; mkdir -p "$tmp"
    cp "$src/package.json" "$tmp/"
    [[ -f "$src/package-lock.json" ]] && cp "$src/package-lock.json" "$tmp/"
    (cd "$tmp" && npm install --no-progress "$@" >/dev/null) || die "npm install failed for $name"
    # Electron's package no longer fetches its binary at install time (no
    # postinstall since ~v42) - lib/electron.sh runs this same install.js
    # on the target when online; offline it has to already be in dist/.
    if [[ -f "$tmp/node_modules/electron/install.js" ]]; then
        (cd "$tmp" && node node_modules/electron/install.js) || die "Electron binary download failed"
    fi
    tar -czf "$OUT_DIR/npm/${name}-node_modules.tar.gz" --owner=0 --group=0 -C "$tmp" node_modules
    info "$name: $(du -sh "$tmp/node_modules" | cut -f1) -> $(du -h "$OUT_DIR/npm/${name}-node_modules.tar.gz" | cut -f1) compressed"
    rm -rf "$tmp"
}

build_modules kiosk-app "$REPO_DIR/kiosk-app"
tar -tzf "$OUT_DIR/npm/kiosk-app-node_modules.tar.gz" node_modules/electron/dist/electron >/dev/null 2>&1 \
    || die "Electron binary missing from the built kiosk-app modules (download blocked?)"
build_modules webui "$REPO_DIR/webui" --omit=dev

################################################################################

electron_ver="$(tar -xzOf "$OUT_DIR/npm/kiosk-app-node_modules.tar.gz" node_modules/electron/package.json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
{
    echo "Ubuntu Based Kiosk offline bundle"
    echo "Built:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Ubuntu:    $codename (resolved against $(basename "$SRC_ISO"))"
    echo "Packages:  ${#debs[@]} .debs for: ${packages[*]}"
    echo "Node.js:   ${node_deb}"
    echo "Electron:  $electron_ver"
} > "$OUT_DIR/bundle-info.txt"

info "Bundle: $(du -sh "$OUT_DIR" | cut -f1) (${#debs[@]} packages, Node.js $(node -v), Electron $electron_ver)"
