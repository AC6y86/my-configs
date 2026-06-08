# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Personal dotfiles and helper scripts for a **Windows 11 + WSL2 (Ubuntu)** workstation used for Meta engineering plus some personal infra. There is no build/test/lint — everything here is shell, PowerShell, AutoHotkey, and one Python script that get installed by symlink or copy and run directly. Changes take effect by re-sourcing/re-running, not compiling.

The git root is `my-configs/`; the `windows/` subdirectory holds Windows-side config. Most scripts assume the home dir is `/home/joepaley` and the Windows user is `joepaley`, with WSL reaching the Windows filesystem via `/mnt/c/...`.

## Install / activate changes

- **`.bashrc`**: symlinked into `~` (`ln -s my-configs/.bashrc ~/.bashrc`). After editing, `source ~/.bashrc`. It sources `~/.bashrc_local` (machine-specific, untracked) near the end, then prepends `~/my-configs/bin` to `PATH` — so anything in `bin/` is runnable by name.
- **`windows/autohotkey.ahk`**: to autostart on login, copy it to
  `C:\Users\joepaley\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`.
  (It is not symlinked; re-copy after editing to update the running version, or restart the script.)
- **`bin/` scripts**: already on `PATH` via `.bashrc`. `ssh_local` is aliased to `python3 ~/my-configs/ssh_local.py`.

## The WSL → Windows boundary (the main architectural theme)

Scripts deliberately bridge WSL2 and Windows because each side owns different tools. Understand which side a script runs on before editing:

- **Windows-side executables invoked from WSL** via `/mnt/c/...`: `dev.exe` (Meta Dev CLI), `ssh.exe`/`scp.exe` (`/mnt/c/Windows/System32/OpenSSH/`), `adb.exe`, `wt.exe` (Windows Terminal). The dev-server scripts call **Windows** `ssh.exe`, not WSL's `ssh`, so they use the Windows SSH key/agent and `dev.exe`'s Kerberos session.
- **SSH key syncing**: `ssh_local.py` calls `sync_ssh_to_windows_symlink.sh` after a successful connection, which copies `~/.ssh/*` to `~/joepaley/.ssh` (`~/joepaley` is a symlink to `/mnt/c/Users/joepaley`) so Windows tools see the same keys.
- **ADB path detection**: `bin/adb` is a wrapper that probes known Windows `adb.exe` locations (Maui, Android SDK) and `exec`s the first it finds — WSL talks to the Windows ADB server so USB devices are visible.

## Connecting to dev servers (Meta On-Demand)

Two parallel implementations of the same idea (find running OD/devserver hosts via `dev.exe list`, then connect with Windows OpenSSH):

- **`od/devssh.sh`** — the fuller version: OD instances, persistent devservers, `-c` dedicated host for "myclaw", tmux attach/create (`-t`/`-a`), host selection by index or name (`-H`), `-l` list. Connects to `<host>.fbinfra.net`.
- **`devssh.sh`** (root) — older/simpler variant, OD instances only. Prefer `od/devssh.sh` when adding features; keep them consistent if you touch the host-discovery logic (parsing `dev.exe list` output with `grep -oP`).
- **`od/devsync.ps1`** — PowerShell (requires PS7). Same host discovery, then rsync (preferred, delta sync) or scp fallback to sync a `persistent/` dir. Has Windows→cygwin path conversion for rsync. `-Push`/`-DryRun`/`-Delete`/`-Exclude`.

## Other SSH/host helpers

- **`ssh_local.py`** — connects to LAN/personal hosts. Resolves a name via the `HOSTNAME_MAP` dict (hardcoded IPs), else tries `<name>.joepaley` / `<name>.joepaley.com`; caches usernames in `~/.ssh_local_usernames.json`, remembers the last host in `/tmp`, auto-runs `ssh-copy-id` on auth failure, and appends an entry to `~/.ssh/config`. Add new known hosts via `HOSTNAME_MAP` + `DEFAULT_USERNAMES`.
- **`ssh_claw.sh`** / **`ssh_digitalocean.sh`** — fixed-host SSH shortcuts (Tailscale IP / DigitalOcean droplet). IPs are hardcoded.
- **`mount_batocera.sh`** — CIFS mount of a Batocera box (hardcoded LAN IP/creds).

## Android logcat tooling (`bin/`)

- **`monitor_logcat.sh`** — filtered, colorized logcat with auto-reconnect. Filters live in `bin/.logcat_filters` (drop lines matching these patterns) and `bin/.logcat_whitelist` (always-keep patterns, override filters). Edit those files to tune noise.
- **`enable_adb_wifi.sh`** (run on the USB-connected machine) → **`connect_adb_wifi.sh`** (run on the remote machine) — pair to switch a device to ADB-over-WiFi.

## Conventions when editing here

- These are personal configs: IPs, hostnames, usernames (`joepaley`), and paths are intentionally hardcoded. Add new endpoints to the existing maps/variables rather than introducing config files.
- The AutoHotkey script (`windows/autohotkey.ahk`) implements Emacs-style keybindings globally, with an `is_target()` allowlist of windows (terminals, VNC, Vim) where the remapping is suppressed — add classes there to exempt an app.
