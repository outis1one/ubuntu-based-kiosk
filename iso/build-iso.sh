#!/bin/bash
################################################################################
# iso/build-iso.sh - Build an Ubuntu Server 26.04 install ISO with the
# kiosk built in, so there's no separate "install Ubuntu, then clone and
# run ./install.sh" step.
#
# What the ISO does:
#   1. Boots the stock Ubuntu Server installer (Subiquity), driven by an
#      autoinstall.yaml at the root of the ISO. By default it still asks
#      for network, disk and your admin username/password - everything
#      else (language, keyboard, SSH server, snaps...) is answered for
#      you. Flags below make any of those automatic too.
#   2. At the end of the install (autoinstall late-commands), copies this
#      repo to /opt/ubuntu-based-kiosk on the new system and enables a
#      one-shot first-boot service (firstboot/kiosk-firstboot.service).
#   3. On the first boot of the installed system, that service takes over
#      tty1 and runs ./install.sh as your admin user from
#      ~/ubuntu-based-kiosk - interactively by default (same prompts as a
#      manual install), or with --unattended taking every default and
#      rebooting straight into the kiosk. Configure sites afterwards via
#      the Web UI (http://<ip>:8090) or ./install.sh.
#
# Nothing in the original ISO is changed except /boot/grub/grub.cfg
# (menu title, plus the `autoinstall` kernel argument with --no-confirm);
# boot records (BIOS + UEFI) are replayed from the original as-is.
#
# Requirements (on the build machine, any recent Ubuntu/Debian): the
# script checks for its build tools and offers to install whatever's
# missing with apt (or pass --install-deps to just do it). By hand:
#   sudo apt install xorriso curl git openssl
# plus, for --offline (amd64 build machine only):
#   sudo apt install apt-utils python3 gnupg ubuntu-keyring
#
# Usage:
#   iso/build-iso.sh [options]
#
#   --iso PATH            Use this Ubuntu Server ISO instead of downloading.
#   --install-deps        Install missing build tools with apt without asking.
#   --release VER         Ubuntu release to download (default: 26.04 - picks
#                         the newest 26.04.x live-server-amd64 point release).
#   --output PATH         Output ISO (default: iso/build/ubuntu-<ver>-kiosk-amd64.iso)
#
#   Installed system:
#   --username NAME       Admin username (the account you SSH in with and run
#                         ./install.sh as - must not be "kiosk"). Giving this
#                         makes the installer's identity screen automatic.
#   --password PASS       Admin password (prompted for if --username is given
#                         without it, or read from $KIOSK_ADMIN_PASSWORD -
#                         better than this flag on shared machines/CI, where
#                         command lines are visible). Stored on the ISO only
#                         as a SHA-512 crypt hash.
#   --hostname NAME       Hostname (default: kiosk).
#   --realname NAME       Full name for the admin account (default: Kiosk Admin).
#   --ssh-key FILE        Add this public key file to the admin user's
#                         authorized_keys.
#   --locale LOCALE       Default: en_US.UTF-8
#   --keyboard LAYOUT     Default: us
#   --auto-storage        Don't ask about disks: wipe the largest disk and use
#                         all of it (LVM). DESTROYS DATA on that disk.
#   --auto-network        Don't show the network screen (DHCP on wired
#                         interfaces). Leave this off if you need WiFi.
#   --no-confirm          Don't ask "Continue with autoinstall?" at boot.
#   --fully-automatic     Shorthand for --auto-storage --auto-network
#                         --no-confirm --unattended; needs --username.
#                         Booting this ISO will wipe a disk with NO questions.
#
#   Kiosk install on first boot:
#   --unattended          Run install.sh with all defaults, no prompts
#                         (skips the Core Settings menu), then reboot.
#   --repo-url URL        git remote recorded in the copied repo, used by
#                         Advanced -> Upgrade (default: this checkout's
#                         origin, else the upstream GitHub repo).
#   --offline             Also bundle everything install.sh downloads (~520 MB:
#                         every apt package incl. the CUPS, LMS/Squeezelite,
#                         Asterisk Intercom, VNC, WireGuard and hotspot addons,
#                         Node.js, prebuilt Electron/Web UI node_modules), so
#                         first boot can install the kiosk with NO internet.
#                         With internet it still installs online as usual;
#                         offline it waits 90s, then uses the bundle. The
#                         bundle stays on the kiosk at /opt/kiosk-offline
#                         - Addons -> CUPS Printing then installs from it too
#                         whenever the kiosk is offline.
#
# The repo copied onto the ISO is a clone of this checkout's current HEAD
# (committed changes only - uncommitted edits are NOT included).
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DEFAULT_REPO_URL="https://github.com/outis1one/ubuntu-based-kiosk.git"

SRC_ISO=""
RELEASE="26.04"
OUTPUT=""
ADMIN_USER=""
ADMIN_PASS="${KIOSK_ADMIN_PASSWORD:-}"
HOSTNAME_="kiosk"
REALNAME="Kiosk Admin"
SSH_KEY_FILE=""
LOCALE="en_US.UTF-8"
KEYBOARD="us"
AUTO_STORAGE=0
AUTO_NETWORK=0
NO_CONFIRM=0
UNATTENDED=0
OFFLINE=0
INSTALL_DEPS=0
REPO_URL=""

# Usernames the Ubuntu installer rejects (system users/groups) - copied
# from subiquity's reserved-usernames so a bad --username fails here
# instead of at boot with "Username is reserved by the system".
RESERVED_USERNAMES="
    root daemon bin sys sync games man lp mail news uucp proxy www-data
    backup list irc gnats nobody adm tty disk kmem dialout fax voice cdrom
    floppy tape sudo audio dip operator src shadow utmp video sasl plugdev
    staff users nogroup netplan ftn mysql tac-plus alias qmail qmaild
    qmails qmailr qmailq qmaill qmailp asterisk vpopmail vchkpw slurm
    hacluster haclient grsec-tpe grsec-sock-all grsec-sock-clt
    grsec-sock-srv grsec-proc ceph opensrf libvirt-qemu admin Debian-exim
    bind crontab cupsys dcc dhcp dictd dnsmasq dovecot fetchmail firebird
    ftp fuse gdm haldaemon hplilp identd input jwhois klog kvm lpadmin maas
    messagebus mythtv netdev powerdev radvd render saned sbuild scanner sgx
    slocate ssh sshd ssl-cert sslwrap statd syslog telnetd tftpd
"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
    sed -n '/^# Usage:/,/^################/p' "$0" | sed '$d; s/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso) SRC_ISO="$2"; shift 2 ;;
        --release) RELEASE="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --username) ADMIN_USER="$2"; shift 2 ;;
        --password) ADMIN_PASS="$2"; shift 2 ;;
        --hostname) HOSTNAME_="$2"; shift 2 ;;
        --realname) REALNAME="$2"; shift 2 ;;
        --ssh-key) SSH_KEY_FILE="$2"; shift 2 ;;
        --locale) LOCALE="$2"; shift 2 ;;
        --keyboard) KEYBOARD="$2"; shift 2 ;;
        --auto-storage) AUTO_STORAGE=1; shift ;;
        --auto-network) AUTO_NETWORK=1; shift ;;
        --no-confirm) NO_CONFIRM=1; shift ;;
        --unattended) UNATTENDED=1; shift ;;
        --fully-automatic) AUTO_STORAGE=1; AUTO_NETWORK=1; NO_CONFIRM=1; UNATTENDED=1; shift ;;
        --repo-url) REPO_URL="$2"; shift 2 ;;
        --offline) OFFLINE=1; shift ;;
        --install-deps) INSTALL_DEPS=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
done

################################################################################
# Validate
################################################################################

# Build tools: command -> the apt package that provides it.
declare -A DEP_PKG=([xorriso]=xorriso [curl]=curl [git]=git [openssl]=openssl [sha256sum]=coreutils)
if (( OFFLINE )); then
    DEP_PKG+=([apt-ftparchive]=apt-utils [python3]=python3 [gpg]=gnupg [dpkg-deb]=dpkg)
fi
missing_pkgs=()
for cmd in "${!DEP_PKG[@]}"; do
    command -v "$cmd" &>/dev/null || missing_pkgs+=("${DEP_PKG[$cmd]}")
done
if (( OFFLINE )) && [[ ! -r /usr/share/keyrings/ubuntu-archive-keyring.gpg ]]; then
    missing_pkgs+=(ubuntu-keyring)
fi
if (( ${#missing_pkgs[@]} )); then
    mapfile -t missing_pkgs < <(printf '%s\n' "${missing_pkgs[@]}" | sort -u)
    echo "Missing build tools: ${missing_pkgs[*]}"
    command -v apt-get &>/dev/null \
        || die "install them with your package manager and re-run (this script expects Ubuntu/Debian)"
    if (( ! INSTALL_DEPS )); then
        [[ -t 0 ]] || die "install them first: sudo apt install ${missing_pkgs[*]}   (or re-run with --install-deps)"
        read -r -p "Install them now with 'sudo apt install'? [Y/n] " reply
        [[ "${reply,,}" =~ ^(|y|yes)$ ]] || die "install them first: sudo apt install ${missing_pkgs[*]}"
    fi
    sudo apt-get update -q
    sudo apt-get install -y "${missing_pkgs[@]}" || die "couldn't install: ${missing_pkgs[*]}"
fi
if (( OFFLINE )) && [[ "$(dpkg --print-architecture 2>/dev/null)" != "amd64" ]]; then
    die "--offline must be built on an amd64 (64-bit Intel/AMD) machine - it runs the bundled Node.js to build the kiosk's modules"
fi

if [[ -n "$ADMIN_USER" ]]; then
    [[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "invalid username: $ADMIN_USER"
    [[ "$ADMIN_USER" != "kiosk" && "$ADMIN_USER" != "root" ]] \
        || die "username '$ADMIN_USER' is reserved (install.sh creates its own 'kiosk' user)"
    [[ " $(echo $RESERVED_USERNAMES) " != *" $ADMIN_USER "* ]] \
        || die "username '$ADMIN_USER' is reserved by Ubuntu (a system user/group) - pick another"
    if [[ -z "$ADMIN_PASS" ]]; then
        [[ -t 0 ]] || die "--username needs a password: pass --password or set KIOSK_ADMIN_PASSWORD"
        read -r -s -p "Password for $ADMIN_USER: " ADMIN_PASS; echo
        read -r -s -p "Confirm password: " pass2; echo
        [[ "$ADMIN_PASS" == "$pass2" ]] || die "passwords don't match"
        [[ -n "$ADMIN_PASS" ]] || die "empty password"
    fi
elif [[ -n "$ADMIN_PASS" ]]; then
    die "--password needs --username"
fi

if (( AUTO_STORAGE && AUTO_NETWORK && NO_CONFIRM )) && [[ -z "$ADMIN_USER" ]]; then
    die "--fully-automatic (or all of --auto-storage --auto-network --no-confirm) needs --username"
fi

[[ "$HOSTNAME_" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die "invalid hostname: $HOSTNAME_"
[[ -z "$SSH_KEY_FILE" || -r "$SSH_KEY_FILE" ]] || die "can't read --ssh-key file: $SSH_KEY_FILE"

if [[ -z "$REPO_URL" ]]; then
    REPO_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    # Local proxies/mirrors and ssh remotes aren't reachable from a kiosk.
    [[ "$REPO_URL" == https://github.com/* ]] || REPO_URL="$DEFAULT_REPO_URL"
fi

mkdir -p "$BUILD_DIR"
WORK="$(mktemp -d "$BUILD_DIR/work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

################################################################################
# Source ISO - download and verify unless one was given
################################################################################

if [[ -z "$SRC_ISO" ]]; then
    base="https://releases.ubuntu.com/$RELEASE"
    info "Looking up the latest Ubuntu $RELEASE live-server ISO..."
    sums="$(curl -fsSL "$base/SHA256SUMS")" || die "couldn't fetch $base/SHA256SUMS"
    iso_name="$(grep -oE "ubuntu-${RELEASE//./\\.}(\.[0-9]+)?-live-server-amd64\.iso" <<<"$sums" | sort -V | tail -1)"
    [[ -n "$iso_name" ]] || die "no live-server-amd64 ISO listed in $base/SHA256SUMS"
    expected="$(grep -F "*$iso_name" <<<"$sums" | awk '{print $1}')"

    mkdir -p "$BUILD_DIR/cache"
    SRC_ISO="$BUILD_DIR/cache/$iso_name"
    if [[ -f "$SRC_ISO" ]] && echo "$expected  $SRC_ISO" | sha256sum -c --status; then
        info "Using cached $iso_name"
    else
        info "Downloading $iso_name (~3 GB)..."
        curl -fL --retry 5 -C - -o "$SRC_ISO" "$base/$iso_name" \
            || curl -fL --retry 5 -o "$SRC_ISO" "$base/$iso_name"
        info "Verifying checksum..."
        echo "$expected  $SRC_ISO" | sha256sum -c --status \
            || { rm -f "$SRC_ISO"; die "checksum mismatch for $iso_name - deleted, re-run to retry"; }
    fi
fi
[[ -f "$SRC_ISO" ]] || die "ISO not found: $SRC_ISO"

if [[ -z "$OUTPUT" ]]; then
    src_base="$(basename "$SRC_ISO" .iso)"
    kind="kiosk"; (( OFFLINE )) && kind="kiosk-offline"
    OUTPUT="$BUILD_DIR/${src_base/-live-server/-$kind}.iso"
    [[ "$OUTPUT" != "$BUILD_DIR/$src_base.iso" ]] || OUTPUT="$BUILD_DIR/${src_base}-$kind.iso"
fi

################################################################################
# Stage the repo + first-boot files that go on the ISO under /kiosk
################################################################################

# Branch the copied repo is on - what Advanced -> Upgrade pulls. CI
# checkouts (actions/checkout) are a detached HEAD, so fall back to the
# branch CI says it built, then main.
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" != "HEAD" ]] || BRANCH="${GITHUB_REF_NAME:-main}"
COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"

info "Staging repo ($BRANCH @ ${COMMIT:0:7})..."
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "    WARNING: uncommitted changes in $REPO_ROOT are NOT included - commit them first if you need them."
fi
mkdir -p "$WORK/kiosk/firstboot"
# init + fetch by commit rather than `git clone --branch`, which can't
# clone a detached HEAD.
stage_repo="$WORK/kiosk/ubuntu-based-kiosk"
git init --quiet "$stage_repo"
git -C "$stage_repo" fetch --quiet --depth 1 "file://$REPO_ROOT" "$COMMIT"
git -C "$stage_repo" checkout --quiet -B "$BRANCH" FETCH_HEAD
git -C "$stage_repo" remote add origin "$REPO_URL"
git -C "$stage_repo" config "branch.$BRANCH.remote" origin
git -C "$stage_repo" config "branch.$BRANCH.merge" "refs/heads/$BRANCH"

install -m 755 "$SCRIPT_DIR/firstboot/kiosk-firstboot" "$WORK/kiosk/firstboot/"
install -m 644 "$SCRIPT_DIR/firstboot/kiosk-firstboot.service" "$WORK/kiosk/firstboot/"
install -m 755 "$SCRIPT_DIR/firstboot/kiosk-offline-apt" "$WORK/kiosk/firstboot/"
cat > "$WORK/kiosk/firstboot/kiosk-firstboot.conf" <<EOF
# Read by /usr/local/sbin/kiosk-firstboot. Written by iso/build-iso.sh.
# 1 = take every install.sh default and reboot into the kiosk; 0 = interactive.
KIOSK_UNATTENDED=$UNATTENDED
EOF

if (( OFFLINE )); then
    info "Building offline bundle (packages, Node.js, Electron)..."
    "$SCRIPT_DIR/offline/build-bundle.sh" "$WORK/kiosk/offline" "$SRC_ISO" "$stage_repo" "$BUILD_DIR/offline-cache"
fi

################################################################################
# autoinstall.yaml
################################################################################

# Single-quoted YAML scalar.
yq() { printf "'%s'" "${1//\'/\'\'}"; }

interactive=()
(( AUTO_NETWORK )) || interactive+=(network)
(( AUTO_STORAGE )) || interactive+=(storage)
[[ -n "$ADMIN_USER" ]] || interactive+=(identity)

{
    echo "#cloud-config"
    echo "# Generated by iso/build-iso.sh - see that file for what this does."
    echo "autoinstall:"
    echo "  version: 1"
    if (( ${#interactive[@]} )); then
        echo "  interactive-sections:"
        for s in "${interactive[@]}"; do echo "    - $s"; done
    fi
    echo "  locale: $(yq "$LOCALE")"
    echo "  keyboard:"
    echo "    layout: $(yq "$KEYBOARD")"
    # Pre-selected answer for the storage screen when it's interactive;
    # the whole answer when --auto-storage.
    echo "  storage:"
    echo "    layout:"
    echo "      name: lvm"
    echo "      sizing-policy: all"
    if [[ -n "$ADMIN_USER" ]]; then
        echo "  identity:"
        echo "    hostname: $(yq "$HOSTNAME_")"
        echo "    realname: $(yq "$REALNAME")"
        echo "    username: $(yq "$ADMIN_USER")"
        echo "    password: $(yq "$(openssl passwd -6 -stdin <<<"$ADMIN_PASS")")"
    fi
    echo "  ssh:"
    echo "    install-server: true"
    echo "    allow-pw: true"
    if [[ -n "$SSH_KEY_FILE" ]]; then
        echo "    authorized-keys:"
        while IFS= read -r key; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            echo "      - $(yq "$key")"
        done < "$SSH_KEY_FILE"
    fi
    cat <<'EOF'
  late-commands:
    - mkdir -p /target/opt /target/usr/local/sbin /target/var/lib/kiosk-firstboot
    - cp -a /cdrom/kiosk/ubuntu-based-kiosk /target/opt/ubuntu-based-kiosk
    - chmod -R u+w /target/opt/ubuntu-based-kiosk
    - install -m 755 /cdrom/kiosk/firstboot/kiosk-firstboot /target/usr/local/sbin/kiosk-firstboot
    - install -m 644 /cdrom/kiosk/firstboot/kiosk-firstboot.service /target/etc/systemd/system/kiosk-firstboot.service
    - install -m 644 /cdrom/kiosk/firstboot/kiosk-firstboot.conf /target/etc/kiosk-firstboot.conf
    - install -m 755 /cdrom/kiosk/firstboot/kiosk-offline-apt /target/usr/local/sbin/kiosk-offline-apt
    - touch /target/var/lib/kiosk-firstboot/pending
    - curtin in-target --target=/target -- systemctl enable kiosk-firstboot.service
EOF
    if (( OFFLINE )); then
        echo "    - cp -a /cdrom/kiosk/offline /target/opt/kiosk-offline"
        echo "    - chmod -R u+w,a+rX /target/opt/kiosk-offline"
    fi
} > "$WORK/autoinstall.yaml"

################################################################################
# grub.cfg - same file serves BIOS and UEFI boot on the server ISO
################################################################################

xorriso -osirrox on -indev "$SRC_ISO" -extract /boot/grub/grub.cfg "$WORK/grub.cfg" 2>/dev/null \
    || die "couldn't read /boot/grub/grub.cfg from $SRC_ISO - is it an Ubuntu Server ISO?"
chmod u+w "$WORK/grub.cfg"
grep -q '/casper/vmlinuz' "$WORK/grub.cfg" || die "unexpected grub.cfg layout in $SRC_ISO"

sed -i 's/Try or Install Ubuntu Server/Install Ubuntu Based Kiosk/' "$WORK/grub.cfg"
if (( NO_CONFIRM )); then
    sed -i -E '/linux[[:space:]]+\/casper\/vmlinuz/ s/[[:space:]]+---/ autoinstall ---/' "$WORK/grub.cfg"
fi

################################################################################
# Write the new ISO
################################################################################

info "Writing $OUTPUT..."
rm -f "$OUTPUT"
xorriso -indev "$SRC_ISO" -outdev "$OUTPUT" \
    -map "$WORK/autoinstall.yaml" /autoinstall.yaml \
    -map "$WORK/kiosk" /kiosk \
    -map "$WORK/grub.cfg" /boot/grub/grub.cfg \
    -boot_image any replay \
    -padding included \
    > "$WORK/xorriso.log" 2>&1 \
    || { cat "$WORK/xorriso.log" >&2; rm -f "$OUTPUT"; die "xorriso failed"; }

echo
info "Done: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
echo
echo "Installer asks for : ${interactive[*]:-nothing}$( (( NO_CONFIRM )) || echo " (plus a 'Continue with autoinstall?' confirmation)")"
echo "Admin user         : ${ADMIN_USER:-chosen during install}"
echo "First boot         : $( (( UNATTENDED )) && echo "unattended install.sh, then reboots into the kiosk" || echo "interactive install.sh on the console")"
echo "Offline bundle     : $( (( OFFLINE )) && echo "yes - installs with no internet (used after 90s offline)" || echo "no - first boot needs internet (add --offline to bundle everything)")"
echo
echo "Write it to a USB stick (replace /dev/sdX - this erases it):"
echo "  sudo dd if='$OUTPUT' of=/dev/sdX bs=4M status=progress oflag=sync"
if (( AUTO_STORAGE && NO_CONFIRM )); then
    echo
    echo "WARNING: this ISO wipes the target's largest disk without asking. Label the stick."
fi
