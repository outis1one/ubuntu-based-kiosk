#!/bin/bash
################################################################################
# iso/e2b-contig.sh - Make a file on a USB drive contiguous, from Linux.
#
# Easy2Boot (and other multiboot loaders) can only boot some ISO files when
# they sit on the drive in one unbroken piece. A big ISO copied onto a
# well-used drive usually lands in several pieces, and Linux has no
# defragmenter for NTFS/FAT32/exFAT. This rewrites the one file so it is
# contiguous, using only ordinary file operations - it never writes
# filesystem structures directly, so the worst case is "still not
# contiguous", not a damaged drive.
#
# How: a plain copy just fills the drive's scattered free gaps again. So
#   1. fill the free space with temporary filler files (plugging every gap),
#   2. find the longest physically unbroken run among them and free exactly
#      that run,
#   3. write the copy - the only free space left is that run,
#   4. delete the fillers, verify the copy's SHA-256, swap it in.
# This writes about as much data as the drive has free (progress shown) -
# minutes on USB 3, longer on USB 2 or a nearly empty big drive.
#
# If there's no unbroken run as big as the file while the original is still
# on the drive, --move-out first parks the original on this computer's disk
# (checksummed), deletes it from the drive to free its pieces, and retries.
#
# Usage:
#   sudo iso/e2b-contig.sh [--check] [--move-out] [--temp-dir DIR] [--yes] FILE...
#
#   --check       Only report whether each file is contiguous.
#   --move-out    Allowed to park the original on this computer if needed
#                 (default temp dir: /var/tmp).
#   --temp-dir D  Where to park it.
#   --yes         Don't ask for confirmation.
#
# Works with NTFS (ntfs-3g or the ntfs3 kernel driver), FAT32 and exFAT -
# anything filefrag can map. Run as root (filefrag needs it on most of
# these filesystems).
################################################################################

set -uo pipefail

CHECK_ONLY=0
MOVE_OUT=0
ASSUME_YES=0
TEMP_DIR=/var/tmp
# Filler size. Small enough that fillers fit inside the drive's free gaps
# (a filler spanning two gaps can't be part of an unbroken run); kept in
# subfolders of 1000 because FAT32 caps the number of files per folder.
CHUNK_MB=4

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

FILES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=1; shift ;;
        --move-out) MOVE_OUT=1; shift ;;
        --temp-dir) TEMP_DIR="$2"; shift 2 ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        -h|--help) sed -n '/^# Usage:/,/^################/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        -*) die "unknown option: $1" ;;
        *) FILES+=("$1"); shift ;;
    esac
done
(( ${#FILES[@]} )) || die "no file given - usage: sudo $0 [--check] FILE..."
[[ $EUID -eq 0 ]] || die "run with sudo (filefrag needs root on NTFS/FAT/exFAT)"
for cmd in filefrag findmnt blkid sha256sum dd awk df stat; do
    command -v "$cmd" &>/dev/null || die "'$cmd' not found (packages: e2fsprogs, util-linux, coreutils)"
done

# extents FILE -> "physical_start physical_end" per extent (filesystem
# blocks), in file order. Empty output = couldn't map (unsupported).
extents() {
    filefrag -e "$1" 2>/dev/null | awk '
        /^ *[0-9]+:/ {
            gsub(/\.\./, " "); gsub(/:/, " ")
            # fields: idx logical_start logical_end physical_start physical_end length ...
            print $4, $5
        }'
}

# Block size filefrag reports in.
fs_block_size() {
    filefrag -e "$1" 2>/dev/null | sed -n 's/.*(\([0-9]*\) blocks of \([0-9]*\) bytes).*/\2/p' | head -1
}

# pieces FILE -> number of physically separate pieces (adjacent extents
# count as one; filefrag splits long runs into several extents).
pieces() {
    extents "$1" | awk 'NR==1 {n=1; prev=$2; next} { if ($1 != prev + 1) n++; prev=$2 } END { print n+0 }'
}

confirm() {
    (( ASSUME_YES )) && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "${reply,,}" == y || "${reply,,}" == yes ]]
}

FILL_DIR=""
TMP_COPY=""
cleanup() {
    [[ -n "$FILL_DIR" && -d "$FILL_DIR" ]] && rm -rf -- "$FILL_DIR"
    [[ -n "$TMP_COPY" && -f "$TMP_COPY" ]] && rm -f -- "$TMP_COPY"
    sync
}
trap cleanup EXIT
trap 'echo; echo "Interrupted - removing temporary files..."; exit 130' INT TERM

# fill_and_carve MOUNT NEED_BYTES -> 0 if it left exactly one free run of at
# least NEED_BYTES (fillers stay in $FILL_DIR until cleanup), 1 if no such run.
fill_and_carve() {
    local mnt="$1" need="$2"
    FILL_DIR="$mnt/.e2b-contig-fill.$$"
    mkdir -p "$FILL_DIR" || return 1
    local free_mb
    free_mb=$(( $(df -B1M --output=avail "$mnt" | tail -1) ))
    info "Filling $free_mb MB of free space with temporary files to plug the gaps..."
    local n=0 written=0 fname
    while :; do
        n=$((n + 1))
        fname="$FILL_DIR/d$(printf %04d $((n / 1000)))/f$(printf %07d $n)"
        mkdir -p "${fname%/*}" 2>/dev/null || break
        # dd stops (keeping what it wrote) when the drive is full.
        dd if=/dev/zero of="$fname" bs=1M count="$CHUNK_MB" status=none 2>/dev/null
        local rc=$?
        local sz
        sz=$(stat -c %s "$fname" 2>/dev/null || echo 0)
        written=$((written + sz))
        (( n % 25 == 0 )) && printf '\r    %d / %d MB' "$((written / 1048576))" "$free_mb"
        (( rc != 0 || sz < CHUNK_MB * 1048576 )) && break
    done
    printf '\r    %d / %d MB\n' "$((written / 1048576))" "$free_mb"
    sync

    # Single-piece fillers sorted by physical position; the longest chain
    # where each starts right after the previous ends is the best run.
    local bs
    bs=$(fs_block_size "$FILL_DIR/d0000/f0000001")
    [[ -n "$bs" ]] || { echo "    Couldn't map the filler files (filefrag unsupported here)."; return 1; }
    # The map lives on this computer, not on the (now full) drive.
    local f list
    list=$(mktemp) || return 1
    info "Mapping where the filler files landed..."
    for f in "$FILL_DIR"/d*/f*; do
        [[ -s "$f" ]] || continue
        # One filefrag call per filler (there can be thousands): keep it only
        # if it's a single piece, as "start end path".
        extents "$f" | awk -v f="$f" '
            NR == 1 { s = $1; e = $2; n = 1; next }
            { if ($1 == e + 1) e = $2; else n++ }
            END { if (NR > 0 && n == 1) print s, e, f }' >> "$list"
    done
    local best
    best=$(sort -n "$list" | awk -v bs="$bs" '
        { if (NR == 1 || $1 != prev_end + 1) { start_line = NR; run_bytes = 0; files = "" }
          run_bytes += ($2 - $1 + 1) * bs; files = files " " $3; prev_end = $2
          if (run_bytes > best_bytes) { best_bytes = run_bytes; best_files = files } }
        END { print best_bytes + 0, best_files }')
    rm -f -- "$list"
    local best_bytes=${best%% *}
    info "Longest unbroken free run found: $((best_bytes / 1048576)) MB (need $((need / 1048576)) MB)"
    if (( best_bytes < need )); then
        return 1
    fi
    # Free just enough of that run (from its start) for the file - keeping the
    # rest plugged so the copy can't wander elsewhere.
    local freed=0 g
    for g in ${best#* }; do
        (( freed >= need )) && break
        freed=$((freed + $(stat -c %s "$g")))
        rm -f -- "$g"
    done
    sync
    return 0
}

# restore_parked PARKED FILE SUM - copy a parked original back onto the
# drive (not contiguous - just safe) and only delete the parked copy once
# the restored one verifies.
restore_parked() {
    local parked="$1" file="$2" sum="$3"
    info "Putting the original back..."
    if cp -- "$parked" "$file" && [[ "$(sha256sum "$file" | cut -d' ' -f1)" == "$sum" ]]; then
        rm -f -- "$parked"
        echo "    Original restored (unchanged, still in pieces)."
    else
        echo "    !! Couldn't verify the restored file - the original is kept safe at $parked"
    fi
}

# make_contiguous FILE
make_contiguous() {
    local file="$1"
    [[ -f "$file" ]] || { echo "$file: not a file"; return 1; }
    file=$(realpath "$file")
    local mnt fstype dev
    read -r dev fstype mnt < <(findmnt -n -o SOURCE,FSTYPE,TARGET --target "$file")
    local size
    size=$(stat -c %s "$file")
    local p
    p=$(pieces "$file")
    echo
    echo "$file"
    echo "    drive: $dev ($fstype) mounted at $mnt, size $((size / 1048576)) MB"
    if [[ -z "$(extents "$file")" ]]; then
        echo "    Can't read this file's layout through this driver ($fstype)."
        # FUSE drivers (fusefat, exfat-fuse) can't map files; the kernel
        # drivers can - and ntfs-3g usually can, but ntfs3 always can.
        local real kdrv=""
        real=$(blkid -o value -s TYPE "$dev" 2>/dev/null)
        case "$real" in
            ntfs) kdrv=ntfs3 ;;
            exfat) kdrv=exfat ;;
            vfat|msdos) kdrv=vfat ;;
        esac
        if [[ -n "$kdrv" ]]; then
            echo "    Remount it with the kernel's $kdrv driver and retry:"
            echo "      sudo umount $dev && sudo mount -t $kdrv $dev $mnt"
        fi
        return 1
    fi
    if [[ "$p" == 1 ]]; then
        echo "    Contiguous (1 piece) - nothing to do."
        return 0
    fi
    echo "    NOT contiguous: $p pieces."
    (( CHECK_ONLY )) && return 2

    confirm "    Rewrite it in one piece? (temporarily fills the drive's free space)" || { echo "    Skipped."; return 2; }

    info "Checksumming the original..."
    local sum
    sum=$(sha256sum "$file" | cut -d' ' -f1)

    local source="$file" parked=""
    if ! fill_and_carve "$mnt" "$size"; then
        rm -rf -- "$FILL_DIR"; FILL_DIR=""; sync
        if (( ! MOVE_OUT )); then
            echo "    Not enough unbroken free space with the original still on the drive."
            echo "    Re-run with --move-out to park the original on this computer meanwhile,"
            echo "    or free up space on the drive (move a few other large files off)."
            return 1
        fi
        local avail
        avail=$(( $(df -B1 --output=avail "$TEMP_DIR" | tail -1) ))
        (( avail > size )) || { echo "    Not enough room in $TEMP_DIR to park it ($((size / 1048576)) MB needed)."; return 1; }
        parked="$TEMP_DIR/$(basename "$file").e2b-contig-parked"
        info "Parking the original in $parked..."
        cp -- "$file" "$parked" && [[ "$(sha256sum "$parked" | cut -d' ' -f1)" == "$sum" ]] \
            || { rm -f -- "$parked"; echo "    Parking copy failed its checksum - nothing changed."; return 1; }
        rm -f -- "$file"; sync
        source="$parked"
        if ! fill_and_carve "$mnt" "$size"; then
            rm -rf -- "$FILL_DIR"; FILL_DIR=""; sync
            echo "    Still no unbroken run big enough."
            restore_parked "$parked" "$file" "$sum"
            echo "    Free up space on the drive (it needs one unbroken $((size / 1048576)) MB area) and retry."
            return 1
        fi
    fi

    TMP_COPY="$(dirname "$file")/.e2b-contig.$$.tmp"
    info "Writing the copy into the freed run..."
    if ! dd if="$source" of="$TMP_COPY" bs=4M conv=fsync status=progress; then
        echo "    Copy failed."
        rm -f -- "$TMP_COPY"; TMP_COPY=""; rm -rf -- "$FILL_DIR"; FILL_DIR=""; sync
        [[ -n "$parked" ]] && restore_parked "$parked" "$file" "$sum"
        return 1
    fi
    rm -rf -- "$FILL_DIR"; FILL_DIR=""
    sync

    local newp
    newp=$(pieces "$TMP_COPY")
    info "Verifying..."
    if [[ "$(sha256sum "$TMP_COPY" | cut -d' ' -f1)" != "$sum" ]]; then
        echo "    !! The copy doesn't match the original's checksum - discarding it."
        rm -f -- "$TMP_COPY"; TMP_COPY=""; sync
        [[ -n "$parked" ]] && restore_parked "$parked" "$file" "$sum"
        return 1
    fi
    if [[ "$newp" != 1 ]]; then
        echo "    The copy still came out in $newp pieces (was $p)."
    fi
    # Same directory, so a rename: the data stays where it was written.
    mv -f -- "$TMP_COPY" "$file" && TMP_COPY=""
    [[ -n "$parked" ]] && rm -f -- "$parked"
    sync
    if [[ "$(pieces "$file")" == 1 ]]; then
        echo "    ✓ Contiguous now (1 piece), checksum verified."
        return 0
    fi
    echo "    Checksum verified, but still $(pieces "$file") pieces - see the notes above."
    return 1
}

rc=0
for f in "${FILES[@]}"; do
    make_contiguous "$f" || rc=1
done
exit "$rc"
