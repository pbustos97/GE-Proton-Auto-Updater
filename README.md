# ge-proton-auto-update

Automatically keeps [GE Proton](https://github.com/GloriousEggroll/proton-ge-custom) up to date for Steam on Linux.

The updater checks GitHub for the [latest GE Proton release](https://github.com/GloriousEggroll/proton-ge-custom/releases/latest) and, if it is not already installed, downloads the correct tarball for your architecture, verifies it against its sha512 checksum, and extracts it into Steam's `compatibilitytools.d` directory.

## Features

- Works with **native Steam** and **Flatpak Steam** (auto-detected)
- **User-level systemd service** — no root needed
- Runs **once per boot**, shortly after login (does not re-run on logout/login within the same boot)
- Skips the download entirely if the latest version is already installed
- Verifies downloads with the release's sha512 checksum

## Requirements

- Linux with **systemd** (user session, standard on all modern distros)
- `bash`, `curl`, `tar`, and `coreutils` (`sha512sum`)

## Installation

```sh
./install.sh
```

This installs, for the current user only:

| What | Where |
|---|---|
| Updater script | `~/.local/bin/ge_proton_update.sh` |
| systemd user unit | `~/.config/systemd/user/ge-proton-update.service` |

It runs automatically on your **next login**. It is deliberately not started at install time.

To test it right away:

```sh
systemctl --user daemon-reload
systemctl --user start ge-proton-update
```

## Checking status and logs

The service runs as a oneshot unit, so its output goes to the systemd user journal:

```sh
journalctl --user -u ge-proton-update        # all runs
journalctl --user -u ge-proton-update -f     # follow (e.g. while testing)
systemctl --user status ge-proton-update     # unit status / last result
```

## Uninstalling

```sh
./install.sh --uninstall
```

This stops and disables the service, removes both installed files, and leaves any GE Proton versions already installed in Steam untouched.

## Standalone usage (no systemd)

`ge_proton_update.sh` can also just be run by hand or from any scheduler:

```sh
./ge_proton_update.sh
```

## Note

After installing a new GE Proton version, restart Steam so it picks up the new entry in `compatibilitytools.d`.

