#!/bin/bash
set -euo pipefail

# Downloads and installs the latest GE Proton release for either a native or
# Flatpak Steam installation. Designed to be run as a systemd user service,
# but works standalone as well.

GE_Proton_Github="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"
steamNativeDir=$HOME/.steam/root
steamFlatpakDir=$HOME/.var/app/com.valvesoftware.Steam/data/Steam
tmpDir=/tmp/proton-update
arch=$(uname -m)

# Logging helper: a stable prefix makes journalctl -u output identifiable
log() { echo "[ge-proton-update] $*"; }

# Always clean up the temp dir and report failure, including when a download,
# checksum, or extraction step aborts under set -e
cleanup() { rc=$?; rm -rf "$tmpDir"; [ $rc -eq 0 ] || log "Update failed (exit $rc)"; }
trap cleanup EXIT

if [ -d "$steamNativeDir" ]; then
    log "Using native Steam install at $steamNativeDir"
    steamDir=$steamNativeDir
elif [ -d "$steamFlatpakDir" ]; then
    log "Using Flatpak Steam install at $steamFlatpakDir"
    steamDir=$steamFlatpakDir
else
    log "Steam is not installed as native or default flatpak"
    log "Update the script to point to the correct directory"
    exit 1
fi

# Set and make compatibility directory (mkdir -p is idempotent)
steamDir=$steamDir/compatibilitytools.d
mkdir -p "$steamDir"

log "Checking latest GE Proton release"
releaseJSON=$(curl -sf --retry 3 "$GE_Proton_Github") || { log "Failed to fetch release information from GitHub"; exit 1; }
version=$(echo "$releaseJSON" | grep tag_name | cut -d\" -f4 || true)
[ -n "$version" ] || { log "Could not determine the latest release version"; exit 1; }

# The tarball extracts to <tag>-<arch> in newer releases (e.g. GE-Proton11-9-x86_64),
# or just <tag> in older ones (e.g. GE-Proton11-3)
if [ -d "$steamDir/$version-$arch" ] || [ -d "$steamDir/$version" ]; then
    log "GE Proton $version is already installed"
    exit 0
fi

rm -rf "$tmpDir" && mkdir -p "$tmpDir" && cd "$tmpDir"

# Resolve download URLs up front so a malformed release is caught early
tarballUrl=$(echo "$releaseJSON" | grep browser_download_url | cut -d\" -f4 | grep "$arch.tar.gz" || true)
checksumUrl=$(echo "$releaseJSON" | grep browser_download_url | cut -d\" -f4 | grep "$arch.sha512sum" || true)
[ -n "$tarballUrl" ] && [ -n "$checksumUrl" ] || { log "Latest release has no $arch tarball"; exit 1; }

log "Downloading $version archives"
curl -fsLOJ --retry 3 "$tarballUrl" && curl -fsLOJ --retry 3 "$checksumUrl"

# Verify the tarball against its sha512sum
sha512sum -c ./*.sha512sum

# Extract, then clean up via the EXIT trap
tar -xf GE-Proton*.tar.gz -C "$steamDir"

log "GE Proton $version installed"
log "Restart Steam if it is open"
