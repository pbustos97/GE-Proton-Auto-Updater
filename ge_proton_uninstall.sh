#!/bin/bash
set -euo pipefail

# Interactive GE Proton uninstaller: choose one or more installed GE Proton
# versions from Steam's compatibilitytools.d directory and delete them.
#
# Works standalone and is NOT wired into any systemd service.
#
# Usage:
#   ./ge_proton_uninstall.sh            Pick GE Proton versions to remove
#   ./ge_proton_uninstall.sh --all      Also list non-GE custom compatibility tools
#   ./ge_proton_uninstall.sh --tags <tag> [tag ...]
#                                       Remove specific tags without the picker
#   ./ge_proton_uninstall.sh --help
#
# Safety notes:
#   - Only directories inside Steam's compatibilitytools.d are touched.
#   - Symlinks are never followed or removed.
#   - A final confirmation lists everything selected before anything is deleted.
#   - Game prefixes (compatdata) of uninstalled versions are left alone.

script_id=ge-proton-uninstall
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$script_dir/lib/common.sh" ]]; then
    source "$script_dir/lib/common.sh"
else
    echo "[$script_id] ERROR: cannot find lib/common.sh next to this script" >&2
    exit 1
fi

if [[ -f "$script_dir/lib/interactive.sh" ]]; then
    source "$script_dir/lib/interactive.sh"
else
    echo "[$script_id] ERROR: cannot find lib/interactive.sh next to this script" >&2
    exit 1
fi

listAll=0
tagMode=0
tagArgs=()

show_usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  (none)        Pick GE Proton versions interactively
  --all         Also list non-GE custom compatibility tools (CachyOS, TKG, ...)
  --tags TAG [TAG ...]
                Remove the given tags without the picker
  -h, --help    Show this help

Optionally set GE_PROTON_STEAM_DIR to override the native Steam root
(useful for testing).
EOF
}

while (( $# > 0 )); do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --all)
            listAll=1
            ;;
        --tags)
            tagMode=1
            shift
            tagArgs=( "$@" )
            set --
            break
            ;;
        *)
            echo "[$script_id] ERROR: unknown argument: $1" >&2
            show_usage >&2
            exit 1
            ;;
    esac
    shift
done

if (( tagMode == 1 && ${#tagArgs[@]} == 0 )); then
    echo "[$script_id] ERROR: --tags requires at least one tag" >&2
    show_usage >&2
    exit 1
fi

detect_steam_dir

# Gather candidate directory names (plain names, no slashes). Symlinks are
# skipped entirely; they are never followed or deleted. Skipped entirely in
# --tags mode, which works on the exact names given.
entries=()
if (( tagMode == 0 )); then
    shopt -s nullglob
    if (( listAll == 1 )); then
        pathList=( "$compatDir"/* )
    else
        pathList=( "$compatDir"/GE-Proton* )
    fi
    shopt -u nullglob
    for candidatePath in "${pathList[@]}"; do
        if [[ -d $candidatePath && ! -L $candidatePath ]]; then
            entries+=( "$(basename "$candidatePath")" )
        elif [[ -L $candidatePath ]]; then
            log "Skipping symlink $(basename "$candidatePath") (symlinks are not removed)"
        fi
    done
fi

# --tags mode: work on the exact names given
if (( tagMode == 1 )); then
    if (( ${#tagArgs[@]} == 0 )); then
        log "--tags requires at least one tag"
        exit 1
    fi
    for tag in "${tagArgs[@]}"; do
        if [[ -z $tag || $tag == *"/"* || $tag == *..* ]]; then
            log "Invalid tag: $tag"
            exit 1
        fi
    done
    entries=()
    for tag in "${tagArgs[@]}"; do
        entries+=( "$tag" )
    done
elif (( ${#entries[@]} == 0 )); then
    if (( listAll == 1 )); then
        log "No compatibility tools installed in $compatDir"
    else
        log "No GE Proton versions installed in $compatDir"
        log "Other custom tools need --all to appear in the list"
    fi
    exit 0
fi

# Default (non --tags) mode: pick from the listing
if (( tagMode == 0 )); then
    lines=()
    for entryName in "${entries[@]}"; do
        lines+=( "$entryName" )
    done
    if ! multi_select "Uninstall which versions? (${#entries[@]} shown, newest first)" "${lines[@]}"; then
        log "Nothing selected; exiting"
        exit 0
    fi
    pickedEntries=()
    for pickIndex in "${PICKED[@]}"; do
        pickedEntries+=( "${entries[pickIndex - 1]}" )
    done
    entries=( "${pickedEntries[@]}" )
fi

# Drop names that do not resolve to a real directory (kept: exists, is a
# directory, and is not a symlink), recording skips
namesPicked=()
skipped=0
for name in "${entries[@]}"; do
    if [[ -n $name && -d "$compatDir/$name" && ! -L "$compatDir/$name" ]]; then
        namesPicked+=( "$name" )
    else
        log "Skipping $name (not found in $compatDir)"
        skipped=$((skipped + 1))
    fi
done

if (( ${#namesPicked[@]} == 0 )); then
    log "Nothing to remove"
    exit 0
fi

log "Selection: ${namesPicked[*]}"
if pgrep -x steam >/dev/null 2>&1; then
    log "Warning: Steam appears to be running. Versions in use may be loaded."
fi
echo "About to permanently remove from $compatDir:"
for name in "${namesPicked[@]}"; do
    echo "  - $name"
done
if ! confirm "Remove these directories permanently?"; then
    log "Removal canceled; nothing was deleted"
    exit 0
fi

failures=0
for name in "${namesPicked[@]}"; do
    target=$compatDir/$name
    # Defense in depth: never touch anything with path-ish characters. Names
    # arrive as plain basenames or --tags values, so these are paranoia guards.
    if [[ -z $name || $name == *"/"* || $name == *..* ]]; then
        log "Refusing to remove unexpected entry: $name"
        failures=$((failures + 1))
        continue
    fi
    if [[ -d $target && ! -L $target ]]; then
        if rm -rf -- "$target"; then
            log "Removed $name"
        else
            log "Failed to remove $name"
            failures=$((failures + 1))
        fi
    else
        log "Failed to remove $name (no longer a directory)"
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    log "Uninstall finished with $failures failure(s); skipped: $skipped"
    exit 1
fi

log "Uninstalled ${#namesPicked[@]} version(s); skipped: $skipped"
notify "GE Proton versions removed" "Restart Steam to refresh the compatibility tool list."
log "Restart Steam if it is open"
