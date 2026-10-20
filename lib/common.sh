#!/bin/bash

# Helpers and constants shared by the GE Proton scripts:
# ge_proton_update.sh, ge_proton_install.sh and ge_proton_uninstall.sh.
#
# The sourcing script sets script_id before including this file so log()
# lines carry the right prefix.

export LC_ALL=C

GE_Proton_Api="https://api.github.com/repos/GloriousEggroll/proton-ge-custom"
steamNativeDir=$HOME/.steam/root
steamFlatpakDir=$HOME/.var/app/com.valvesoftware.Steam/data/Steam
arch=$(uname -m)
script_id=${script_id:-ge-proton}

# Logging helper: a stable prefix makes journalctl -u output identifiable
log() {
    echo "[$script_id] $*"
    return 0
}

# Desktop notification helper: no-op when notify-send (libnotify) is missing
# or no notification daemon is running, and never fails the caller
notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "GE Proton Updater" "$@" 2>/dev/null || true
}

# Detect Steam and set compatDir to its compatibilitytools.d directory.
# Native install preferred over Flatpak. Exits when neither exists.
# GE_PROTON_STEAM_DIR overrides the native Steam root (useful for testing).
detect_steam_dir() {
    if [[ -n ${GE_PROTON_STEAM_DIR:-} ]]; then
        log "Using Steam dir override at $GE_PROTON_STEAM_DIR"
        compatDir=$GE_PROTON_STEAM_DIR/compatibilitytools.d
    elif [[ -d "$steamNativeDir" ]]; then
        log "Using native Steam install at $steamNativeDir"
        compatDir=$steamNativeDir/compatibilitytools.d
    elif [[ -d "$steamFlatpakDir" ]]; then
        log "Using Flatpak Steam install at $steamFlatpakDir"
        compatDir=$steamFlatpakDir/compatibilitytools.d
    else
        log "Steam is not installed as native or default flatpak"
        log "Update the script to point to the correct directory"
        exit 1
    fi
}

# Fetch a GitHub release JSON document. Returns curl's status; callers
# should treat failure as fatal or skip the release.
fetch_release_json() {
    local url=$1
    local rc=0
    curl -sf --retry 3 "$url" || rc=$?
    return "$rc"
}

# Extract tag_name fields from any GitHub release JSON (single object or
# releases array). One tag per line, newest first.
extract_release_tags() {
    grep -oE '"tag_name" *: *"[^"]*"' | cut -d'"' -f4
    return $?
}

# Returns success when the given GE Proton tag already has its extracted
# directory in Steam. Both layout generations covered:
# <tag>-<arch> in newer releases (e.g. GE-Proton11-9-x86_64), or just
# <tag> in older ones (e.g. GE-Proton11-3).
is_installed() {
    local tag=$1
    if [[ -d "$compatDir/$tag-$arch" || -d "$compatDir/$tag" ]]; then
        return 0
    fi
    return 1
}
