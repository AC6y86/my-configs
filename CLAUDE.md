# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal dotfiles and helper scripts used for Meta engineering plus some personal infra. They span **four environments**, and most files target one or two of them:

- **Windows 11 + WSL2 (Ubuntu)** — the original setup: the bash scripts plus a Windows-side cert-agent bridge, reaching the Windows filesystem via `/mnt/c/...`.
- **macOS** — laptop: native `fb-sks-agent`, iTerm2, sshfs.
- **Native Linux (Fedora)** — desktop: the bash/Python scripts run directly.
- **Windows / PowerShell** — the Windows side itself: AutoHotkey, Windows Terminal, the PowerShell profile, and installer scripts.

There is no build/test/lint — everything here is shell, PowerShell, AutoHotkey, and one Python script that get installed by symlink or copy and run directly. Changes take effect by re-sourcing/re-running, not compiling.

The git root is `my-configs/`; the `windows/` subdirectory holds Windows-side config. Scripts assume the username is `joepaley`. Paths and the SSH cert-agent location differ by platform, so cross-platform scripts detect the OS at runtime (e.g. `meta/tmux.sh` picks the `fb-sks-agent` socket per platform) — check that platform split before editing.

## Install / activate changes

- **`.bashrc`** (WSL & native Linux): symlinked into `~` (`ln -s my-configs/.bashrc ~/.bashrc`). After editing, `source ~/.bashrc`. It sources `~/.bashrc_local` (machine-specific, untracked) near the end, then prepends `~/my-configs/bin` to `PATH` — so anything in `bin/` is runnable by name. Some of it is WSL-specific (the `npiperelay`/`socat` cert-agent bridge, `/mnt/c` aliases, `wt.exe` terminal aliases) and simply no-ops or is unused on native Linux/macOS.
- **`windows/autohotkey.ahk`** (Windows-only): to autostart on login it must live in
  `C:\Users\joepaley\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`.
  It is not symlinked. After editing, run `windows/install-autohotkey.ps1`
  (PowerShell) to copy it over the old version and restart the running
  AutoHotkey instance so changes take effect immediately.
- **`bin/` scripts**: already on `PATH` via `.bashrc`. `ssh_local` is aliased to `python3 ~/my-configs/ssh_local.py`.
- **Windows terminal/PowerShell configs** (Windows-only): tracked copies live in
  `windows/powershell/Microsoft.PowerShell_profile.ps1` (live: `$PROFILE`, i.e.
  `C:\Users\joepaley\Documents\PowerShell\...`) and
  `windows/windows-terminal/settings.json` (live:
  `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`).
  Deploy with `windows/install-windows-configs.ps1` (backs up each live file to a
  `.bak-<timestamp>` first). These make WSL/bash and PowerShell behave the same:
  the profile sets PSReadLine to emacs edit mode (matching bash readline), and
  Windows Terminal frees `ctrl+c` for SIGINT with copy/paste on
  `ctrl+shift+c`/`ctrl+shift+v`. Windows Terminal rewrites its `settings.json`
  via the UI, so re-copy the live file back into the repo after intentional UI
  changes. See `windows/WINDOWS_TERMINAL_KEYS.md` for the key-handling rationale.

## Platform boundaries (the main architectural theme)

The trickiest scripts either straddle two OSes or adapt to several. Understand which platform(s) a script targets before editing — the SSH cert agent, file paths, and terminal launcher all differ.

**Windows/WSL bridge.** On WSL each side owns different tools, so scripts reach across `/mnt/c/...`:
- **SSH cert agent**: `.bashrc` bridges the Windows `fb-sks-agent` named pipe into a WSL Unix socket via `npiperelay.exe` + `socat`, exporting `SSH_AUTH_SOCK` so WSL's native `ssh` can use the Meta certificate.
- **Windows-side executables invoked from WSL** via `/mnt/c/...`: `adb.exe`, `wt.exe` (Windows Terminal), and `npiperelay.exe` (run through WSL binfmt interop).
- **SSH key syncing**: `ssh_local.py` calls `sync_ssh_to_windows_symlink.sh` after a successful connection, which copies `~/.ssh/*` to `~/joepaley/.ssh` (`~/joepaley` is a symlink to `/mnt/c/Users/joepaley`) so Windows tools see the same keys.
- **ADB path detection**: `bin/adb` is a wrapper that probes known Windows `adb.exe` locations (Maui, Android SDK) and `exec`s the first it finds — WSL talks to the Windows ADB server so USB devices are visible.

**macOS.** `fb-sks-agent` runs natively at `~/.fb-sks-agent/agent.sock` — no bridge needed; scripts point `SSH_AUTH_SOCK` there. Terminal launcher is iTerm2 (`meta/CreateDevTerm-mac.md`); `meta/devmount.sh` sshfs-mounts the devserver at `/Volumes/devserver`.

**Native Linux (Fedora).** The bash/Python scripts run directly. Where `fb-sks-agent` is present it is used the same way as on macOS (native socket).

**Cross-platform scripts** (e.g. `meta/tmux.sh`) detect the platform at runtime: they prefer the native `~/.fb-sks-agent/agent.sock` when it exists, else fall back to whatever `SSH_AUTH_SOCK` the environment already set (the WSL bridge).

## Connecting to dev servers (Meta)

These live in `meta/` and work on WSL, macOS, and Linux — the SSH cert agent is resolved per platform (see above). `meta/CLAUDE.md` has the full detail; the SSH auth chain and constraints (Duo 2FA per connection, no multiplexing) are documented there.

- **`meta/devssh.sh`** — core SSH connector to `devvm7002.scu0.facebook.com`. `-t [name]` attaches/creates a tmux session. Requires `SSH_AUTH_SOCK` (set by the WSL bridge or the native agent).
- **`meta/tmux.sh`** — interactive arrow-key tmux session manager (list/attach/create/delete) over a single SSH connection (one Duo prompt). Picks the cert agent per platform and is written to run on macOS's system bash 3.2 as well as Linux/WSL bash.
- **`meta/devmount.sh`** — macOS only: sshfs-mounts the devserver home at `/Volumes/devserver` (`mount`/`unmount`/`status`).
- **`meta/devterm.ps1`** (Windows) / **`meta/CreateDevTerm.md`** (Windows) / **`meta/CreateDevTerm-mac.md`** (macOS) / **`meta/CreateDevTerm-linux.md`** (native Linux / GNOME) — launchers that open a terminal straight into `tmux.sh`.

## Other SSH/host helpers

- **`ssh_local.py`** — connects to LAN/personal hosts. Resolves a name via the `HOSTNAME_MAP` dict (hardcoded IPs), else tries `<name>.joepaley` / `<name>.joepaley.com`; caches usernames in `~/.ssh_local_usernames.json`, remembers the last host in `/tmp`, auto-runs `ssh-copy-id` on auth failure, and appends an entry to `~/.ssh/config`. Add new known hosts via `HOSTNAME_MAP` + `DEFAULT_USERNAMES`.
- **`ssh_claw.sh`** / **`ssh_digitalocean.sh`** — fixed-host SSH shortcuts (Tailscale IP / DigitalOcean droplet). IPs are hardcoded.
- **`mount_batocera.sh`** — CIFS mount of a Batocera box (hardcoded LAN IP/creds).

## Android logcat tooling (`bin/`)

- **`monitor_logcat.sh`** — filtered, colorized logcat with auto-reconnect. Filters live in `bin/.logcat_filters` (drop lines matching these patterns) and `bin/.logcat_whitelist` (always-keep patterns, override filters). Edit those files to tune noise.
- **`enable_adb_wifi.sh`** (run on the USB-connected machine) → **`connect_adb_wifi.sh`** (run on the remote machine) — pair to switch a device to ADB-over-WiFi.

## Fedora / GNOME desktop tweaks (`fedora/`)

Native-Linux desktop UX customizations, applied via `gsettings` (stored in dconf, so they persist across reboots — nothing here is symlinked or sourced). **`fedora/gnome-tweaks.md`** is the running record of each tweak with the exact apply/verify/rollback commands. Current environment: Fedora, GNOME Shell 50.2, Wayland; the dock is the **Dash to Dock** extension (`dash-to-dock@micxgx.gmail.com`), configured under the `org.gnome.shell.extensions.dash-to-dock` schema (e.g. `click-action = 'focus-or-appspread'` to fan out all of an app's windows on dock click). Append new tweaks as sections in that file. **`fedora/wezterm.md`** separately records the WezTerm setup (live config `~/.config/wezterm/wezterm.lua`, not tracked here): hardware-accel front end, `enable_wayland = false` for fractional scaling, and font/colors matched to the Ptyxis default terminal (Adwaita Mono 11 + GNOME dark palette).

## Conventions when editing here

- These are personal configs: IPs, hostnames, usernames (`joepaley`), and paths are intentionally hardcoded. Add new endpoints to the existing maps/variables rather than introducing config files.
- The AutoHotkey script (`windows/autohotkey.ahk`) implements Emacs-style keybindings globally, with an `is_target()` allowlist of windows (terminals, VNC, Vim) where the remapping is suppressed — add classes there to exempt an app.
