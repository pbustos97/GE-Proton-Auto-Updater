#!/bin/bash
set -euo pipefail

# Interactive GE Proton installer: choose one or more releases from the
# GitHub release list and install them into Steam's compatibilitytools.d
# directory for a native or Flatpak Steam installation.
#
# Works standalone and is NOT wired into any systemd service; the automated
# updater lives in ge_proton_update.sh.
#
# Usage:
#   ./ge_proton_install.sh                 Pick releases interactively (default: 30 latest)
#   ./ge_proton_install.sh --latest        Install the latest release without the picker
#   ./ge_proton_install.sh --all           List every release (paged, newest first)
#   ./ge_proton_install.sh --tags <tag> [tag ...]
#                                          Install specific tags without the picker
#   ./ge_proton_install.sh --help
#
# Requires bash, curl, tar and coreutils (sha512sum); fzf is optional and
# upgrades the picker when installed.

script_id=ge-proton-install
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmpDir=${TMPDIR:-/tmp}/proton-install

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

listLimit=30
listAll=0
latestOnly=0
tagMode=0
interactivePick=0
tagArgs=()

show_usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  (none)        Pick releases interactively (list of $listLimit latest releases)
  --latest      Install the latest release without the picker
  --all         List every available release (paged), newest first
  --tags TAG [TAG ...]
                Install the given tags without the picker
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
        --latest)
            latestOnly=1
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

# Always clean up the temp dir and report failure, including when a download,
# checksum, or extraction step aborts under set -e
cleanup() {
    rc=$?
    rm -rf "$tmpDir"
    if [[ $rc -ne 0 ]]; then
        log "Install failed (exit $rc)"
        notify -u critical "GE Proton install failed" "See terminal output for details (exit $rc)"
    fi
}
trap cleanup EXIT

detect_steam_dir

# Set and make compatibility directory (mkdir -p is idempotent)
mkdir -p "$compatDir"

# Fetch all release tags, newest first. Uses only one page for the default
# list; --all walks the pages (up to 10, i.e. up to 1000 releases).
load_release_tags() {
    if (( listAll == 0 )); then
        pageJson=$(fetch_release_json "$GE_Proton_Api/releases?per_page=$listLimit") || { log "Failed to fetch release list from GitHub"; exit 1; }
        echo "$pageJson" | extract_release_tags
        return 0
    fi
    local page=1 all=() pageTags
    while (( page <= 10 )); do
        pageJson=$(fetch_release_json "$GE_Proton_Api/releases?per_page=100&page=$page") || { log "Failed to fetch release list (page $page)"; exit 1; }
        mapfile -t pageTags < <(echo "$pageJson" | extract_release_tags)
        if (( ${#pageTags[@]} == 0 )); then
            break
        fi
        all+=( "${pageTags[@]}" )
        if (( ${#pageTags[@]} < 100 )); then
            break
        fi
        (( page++ ))
    done
    printf '%s\n' "${all[@]}"
}

# Determine which tags will be installed
if (( tagMode == 1 )); then
    tags=( "${tagArgs[@]}" )
    log "Non-interactive install of ${#tags[@]} release(s): ${tags[*]}"
elif (( latestOnly == 1 )); then
    latestJson=$(fetch_release_json "$GE_Proton_Api/releases/latest") || { log "Failed to fetch release information from GitHub"; exit 1; }
    latestTag=$(echo "$latestJson" | grep tag_name | cut -d\" -f4 || true)
    if [[ -z $latestTag ]]; then
        log "Could not determine the latest release version"
        exit 1
    fi
    tags=( "$latestTag" )
else
    interactivePick=1
    if ! allTagsRaw=$(load_release_tags); then
        log "Failed to load the release list"
        exit 1
    fi
    mapfile -t allTags <<<"$allTagsRaw"
    if (( ${#allTags[@]} == 0 )); then
        log "No GE Proton releases found on GitHub"
        exit 1
    fi

    lines=()
    for (( i = 0; i < ${#allTags[@]}; i++ )); do
        marker=""
        if is_installed "${allTags[$i]}"; then
            marker=" [installed]"
        fi
        lines+=( "${allTags[$i]}$marker" )
    done

    if ! multi_select "Install which releases? (${#allTags[@]} shown, latest first)" "${lines[@]}"; then
        log "Nothing selected; exiting"
        exit 0
    fi

    tags=()
    for pickIndex in "${PICKED[@]}"; do
        tags+=( "${allTags[pickIndex - 1]}" )
    done
fi

# Handle selections that are already installed: in the picker flow (or with
# --tags/--latest when run interactively) give a chance to skip re-downloading
alreadyInstalledTags=()
for tag in "${tags[@]}"; do
    if is_installed "$tag"; then
        alreadyInstalledTags+=( "$tag" )
    fi
done
if (( ${#alreadyInstalledTags[@]} > 0 )); then
    log "Already installed: ${alreadyInstalledTags[*]}"
    skipInstalled=0
    if (( interactivePick == 1 )) && confirm "Download and re-install them anyway?"; then
        skipInstalled=0
    elif (( interactivePick == 1 )); then
        skipInstalled=1
        log "Keeping existing installations"
    else
        # Non-interactive mode stays deterministic: re-install is skipped
        for tag in "${alreadyInstalledTags[@]}"; do
            log "Skipping $tag (already installed)"
        done
        skipInstalled=1
    fi
    if (( skipInstalled == 1 )); then
        remaining=()
        for tag in "${tags[@]}"; do
            if ! is_installed "$tag"; then
                remaining+=( "$tag" )
            fi
        done
        tags=( "${remaining[@]}" )
    fi
fi
if (( ${#tags[@]} == 0 )); then
    if (( tagMode == 1 )); then
        log "All requested releases are already installed; nothing to install"
    elif (( latestOnly == 1 )); then
        log "The latest release is already installed"
    else
        log "Nothing left to install"
    fi
    log "Restart Steam if it is open"
    exit 0
fi

# Download, verify and extract a single release. Runs in a subshell so that
# a failure aborts only this release and the batch continues.
install_tag() {
    (
        local tag=$1
        tagDir=$tmpDir/$tag
        rm -rf "$tagDir" && mkdir -p "$tagDir" && cd "$tagDir"

        log "Fetching release info for $tag"
        tagJson=$(fetch_release_json "$GE_Proton_Api/releases/tags/$tag") || exit 1

        tarballUrl=$(echo "$tagJson" | grep browser_download_url | cut -d\" -f4 | grep "$arch.tar.gz" || true)
        checksumUrl=$(echo "$tagJson" | grep browser_download_url | cut -d\" -f4 | grep "$arch.sha512sum" || true)
        if [[ -z $tarballUrl || -z $checksumUrl ]]; then
            log "Release $tag has no $arch tarball; skipping"
            exit 1
        fi

        log "Downloading $tag"
        curl -fsLOJ --retry 3 "$tarballUrl" && curl -fsLOJ --retry 3 "$checksumUrl"

        if ! sha512sum -c ./*.sha512sum; then
            log "Checksum verification failed for $tag"
            exit 1
        fi

        # Extract, then drop the tarball immediately to keep temp usage low
        tar -xf GE-Proton*.tar.gz -C "$compatDir"
        rm -rf "$tagDir"

        log "GE Proton $tag installed"
        notify "GE Proton $tag installed" "Restart Steam to pick it up."
    )
}

failures=0
for tag in "${tags[@]}"; do
    if ! install_tag "$tag"; then
        log "Failed to install $tag"
        failures=$((failures + 1))
    fi
done

log "Done: ${#tags[@]} release(s) processed, $(( ${#tags[@]} - failures )) installed, $failures failed"
log "Restart Steam if it is open"
if (( failures > 0 )); then
    exit 1
fi
