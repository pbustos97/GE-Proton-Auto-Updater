#!/bin/bash
set -euo pipefail

# Downloads and installs the latest GE Proton release for either a native or
# Flatpak Steam installation. Designed to be run as a systemd user service,
# but works standalone as well.
#
# Shared code lives in lib/common.sh (or ge-proton-lib/common.sh when
# installed to ~/.local/bin by install.sh). For picking specific releases
# by hand, use ge_proton_install.sh / ge_proton_uninstall.sh instead.

script_id=ge-proton-update
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmpDir=${TMPDIR:-/tmp}/proton-update

if [[ -f "$script_dir/lib/common.sh" ]]; then
    source "$script_dir/lib/common.sh"
elif [[ -f "$script_dir/ge-proton-lib/common.sh" ]]; then
    source "$script_dir/ge-proton-lib/common.sh"
else
    echo "[$script_id] ERROR: cannot find common.sh next to $0" >&2
    exit 1
fi

# Always clean up the temp dir and report failure, including when a download,
# checksum, or extraction step aborts under set -e
cleanup() {
    rc=$?
    rm -rf "$tmpDir"
    if [[ $rc -ne 0 ]]; then
        log "Update failed (exit $rc)"
        notify -u critical "GE Proton update failed" "Check journalctl --user -u ge-proton-update for details (exit $rc)"
    fi
}
trap cleanup EXIT

detect_steam_dir

# Set and make compatibility directory (mkdir -p is idempotent)
mkdir -p "$compatDir"

log "Checking latest GE Proton release"
releaseJSON=$(fetch_release_json "$GE_Proton_Api/releases/latest") || { log "Failed to fetch release information from GitHub"; exit 1; }
version=$(echo "$releaseJSON" | grep tag_name | cut -d\" -f4 || true)
[[ -n "$version" ]] || { log "Could not determine the latest release version"; exit 1; }

if is_installed "$version"; then
    log "GE Proton $version is already installed"
    exit 0
fi

rm -rf "$tmpDir" && mkdir -p "$tmpDir" && cd "$tmpDir"

# Resolve download URLs up front so a malformed release is caught early
tarballUrl=$(echo "$releaseJSON" | grep browser_download_url | cut -d\" -f4 | grep "$arch.tar.gz" || true)
checksumUrl=$(echo "$releaseJSON" | grep browser_download_url | cut -d\" -f4 | grep "$arch.sha512sum" || true)
[[ -n "$tarballUrl" && -n "$checksumUrl" ]] || { log "Latest release has no $arch tarball"; exit 1; }

log "Downloading $version archives"
curl -fsLOJ --retry 3 "$tarballUrl" && curl -fsLOJ --retry 3 "$checksumUrl"

# Verify the tarball against its sha512sum
sha512sum -c ./*.sha512sum

# Extract, then clean up via the EXIT trap
tar -xf GE-Proton*.tar.gz -C "$compatDir"

log "GE Proton $version installed"
log "Restart Steam if it is open"
notify "GE Proton $version installed" "Restart Steam to pick it up."
