# GE Proton Auto Updater

Automatically keeps [GE Proton](https://github.com/GloriousEggroll/proton-ge-custom) up to date for Steam on Linux, with optional interactive tools for installing and removing specific versions.

The updater checks GitHub for the [latest GE Proton release](https://github.com/GloriousEggroll/proton-ge-custom/releases/latest) and, if it is not already installed, downloads the correct tarball for your architecture, verifies it against its sha512 checksum, and extracts it into Steam's `compatibilitytools.d` directory.

## Files

| File | Purpose |
|---|---|
| `ge_proton_update.sh` | Auto-updater; installs the latest release (used by the systemd service) |
| `ge_proton_install.sh` | Interactive installer; pick one or more releases to install |
| `ge_proton_uninstall.sh` | Interactive uninstaller; pick installed releases to remove |
| `lib/common.sh` | Shared helpers (Steam detection, logging, GitHub fetches) |
| `lib/interactive.sh` | Shared picker/confirm helpers for the two interactive scripts |
| `install.sh` | Installs/uninstalls the auto-updater systemd user service |

The two interactive scripts are run manually from the repo and are not wired into any systemd service.

## Features

- Works with **native Steam** and **Flatpak Steam** (auto-detected)
- **User-level systemd service** — no root needed
- Runs **once per boot**, shortly after login (does not re-run on logout/login within the same boot)
- Skips the download entirely if the latest version is already installed
- Verifies downloads with the release's sha512 checksum
- **Desktop notifications** when an update is installed or fails (optional, via `libnotify`)

## Requirements

- Linux with **systemd** (user session, standard on all modern distros)
- `bash`, `curl`, `tar`, and `coreutils` (`sha512sum`)
- `libnotify` (`notify-send`) is **optional** — without it the tools work the same, they just skip the popups. Install it via e.g. `libnotify` (Arch), `libnotify-bin` (Debian/Ubuntu), or `libnotify` (Fedora).
- The interactive scripts additionally use `fzf` when available for a nicer picker; a numbered fallback asks for a token selection otherwise.

## Auto-updater

### Installation

```sh
./install.sh
```

This installs, for the current user only:

| What | Where |
|---|---|
| Updater script | `~/.local/bin/ge_proton_update.sh` |
| Shared library | `~/.local/bin/ge-proton-lib/common.sh` |
| systemd user unit | `~/.config/systemd/user/ge-proton-update.service` |

It runs automatically on your **next login**. It is deliberately not started at install time.

To test it right away:

```sh
systemctl --user daemon-reload
systemctl --user start ge-proton-update
```

### Checking status and logs

The service runs as a oneshot unit, so its output goes to the systemd user journal:

```sh
journalctl --user -u ge-proton-update        # all runs
journalctl --user -u ge-proton-update -f     # follow (e.g. while testing)
systemctl --user status ge-proton-update     # unit status / last result
```

### Uninstalling the service

```sh
./install.sh --uninstall
```

This stops and disables the service, removes the updater script and its shared library, and leaves any GE Proton versions already installed in Steam untouched.

## Installing specific releases (interactive)

```sh
./ge_proton_install.sh
```

Shows a numbered list of the 30 latest releases (newest first, already-installed versions marked `[installed]`) and multi-select which ones to install. With `fzf` installed you get a fuzzy multi-select where `TAB`/`SHIFT-TAB` mark entries; without it, type tokens like `1 3 6-9` (ranges and `a` = pick all supported) and press Enter.

Options:

```sh
./ge_proton_install.sh --all        # walk every available release (newest first)
./ge_proton_install.sh --latest     # install the latest release without the picker
./ge_proton_install.sh --tags GE-Proton10-9 GE-Proton9-27   # install specific tags
./ge_proton_install.sh --help
```

Each selected release is downloaded, verified with its sha512 checksum, and extracted into `compatibilitytools.d`; a failure with one release does not stop the others, and a summary shows how many succeeded.

## Uninstalling versions (interactive)

```sh
./ge_proton_uninstall.sh
```

Lists every installed GE Proton version in `compatibilitytools.d` (same picker as the installer) and removes the ones you select after a confirmation showing exactly what will be deleted.

Options:

```sh
./ge_proton_uninstall.sh --all      # also list non-GE custom compatibility tools
./ge_proton_uninstall.sh --tags GE-Proton9-27 GE-Proton8-5   # remove specific tags
./ge_proton_uninstall.sh --help
```

Safety notes:

- Only directories under Steam's `compatibilitytools.d` are touched; game prefixes (`compatdata`) are left alone.
- Symlinks are never followed or removed.
- Nothing is deleted without a terminal confirmation listing exactly what will be removed; the script refuses to proceed when no TTY is attached.
- It warns before removing a version while Steam is running.

`GE_PROTON_STEAM_DIR` overrides the Steam root for testing (same override applies to all scripts).

## Standalone usage (no systemd)

`ge_proton_update.sh` can also just be run by hand or from any scheduler:

```sh
./ge_proton_update.sh
```

The interactive scripts work the same from anywhere in the repo.

## Note

After installing or removing a GE Proton version, restart Steam so it refreshes the entries in `compatibilitytools.d`.
