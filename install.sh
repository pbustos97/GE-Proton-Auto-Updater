#!/bin/bash
set -euo pipefail

# Installs or uninstalls a systemd user service that runs ge_proton_update.sh
# once per boot at login. Everything is per-user; no root required.
#
# Usage:
#   ./install.sh              Install the service
#   ./install.sh --uninstall  Remove the service and the installed updater

script_name=ge_proton_update.sh
service_name=ge-proton-update.service
unit_name=ge-proton-update
lib_name=lib/common.sh
installed_lib_name=ge-proton-lib

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_script="$repo_dir/$script_name"
source_lib="$repo_dir/$lib_name"
bin_dir=$HOME/.local/bin
installed_script=$bin_dir/$script_name
installed_lib_dir=$bin_dir/$installed_lib_name
installed_lib=$installed_lib_dir/common.sh
unit_dir=$HOME/.config/systemd/user
unit_file=$unit_dir/$service_name

log() {
    echo "[install] $*"
}

die() {
    echo "[install] ERROR: $*" >&2
    exit 1
}

show_usage() {
    echo "Usage: $0 [--uninstall]"
}

do_uninstall() {
    log "Stopping and disabling $service_name"
    systemctl --user stop "$unit_name" 2>/dev/null || true
    systemctl --user disable "$unit_name" 2>/dev/null || true

    log "Removing unit file $unit_file"
    rm -f "$unit_file"

    if [[ -f "$installed_script" ]]; then
        log "Removing updater script $installed_script"
        rm -f "$installed_script"
    fi

    if [[ -d "$installed_lib_dir" ]]; then
        log "Removing shared library $installed_lib_dir"
        rm -rf "$installed_lib_dir"
    fi

    log "Reloading systemd user units"
    systemctl --user daemon-reload

    log "Uninstall complete"
    log "GE Proton versions already installed in Steam were left untouched"
    exit 0
}

case ${1:-} in
    --uninstall)
        do_uninstall
        ;;
    "")
        # fall through to install
        ;;
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        echo "ERROR: unknown argument: $1" >&2
        show_usage
        exit 1
        ;;
esac

# --- Prerequisite checks -----------------------------------------------------

if [[ $(id -u) -eq 0 ]]; then
    die "This installer sets up a per-user service; do not run as root"
fi

if ! command -v systemctl >/dev/null 2>&1; then
    die "systemctl not found; this installer requires systemd"
fi

if ! XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} \
    systemctl --user show-environment >/dev/null 2>&1; then
    die "systemd user bus unavailable (re-login or check XDG_RUNTIME_DIR)"
fi

for cmd in curl sha512sum tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "Required command not found: $cmd"
    fi
done

# Optional: desktop notifications on update success/failure via libnotify
if ! command -v notify-send >/dev/null 2>&1; then
    log "notify-send not found; desktop notifications will be skipped (install libnotify to enable them)"
fi

if [[ ! -f "$source_script" ]]; then
    die "Updater script not found: $source_script (run install.sh from the repo)"
fi

if [[ ! -f "$source_lib" ]]; then
    die "Shared library not found: $source_lib (run install.sh from the repo)"
fi

# --- Install -----------------------------------------------------------------

log "Installing updater script to $installed_script"
mkdir -p "$bin_dir"
install -m 0755 "$source_script" "$installed_script"

log "Installing shared library to $installed_lib"
install -d -m 0755 "$installed_lib_dir"
install -m 0644 "$source_lib" "$installed_lib"

log "Writing unit file $unit_file"
mkdir -p "$unit_dir"
cat >"$unit_file" <<EOF
[Unit]
Description=Update GE Proton to the latest release
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/$script_name

[Install]
WantedBy=default.target
EOF

log "Reloading systemd user units"
systemctl --user daemon-reload

log "Enabling $service_name for future boots"
systemctl --user enable "$unit_name"

log "------------------------------"
log "Install complete"
log "The updater runs once per boot, shortly after you log in"
log "It will NOT run now; to test it manually run:"
log "  systemctl --user start $unit_name"
log "  journalctl --user -u $unit_name -f"
exit 0
