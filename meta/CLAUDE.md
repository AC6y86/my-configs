# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Environment

This repo lives at `C:\Users\joepaley\my-configs` on Windows 11 and is mapped into WSL (Ubuntu) at `~/my-configs`. The `meta/` subdirectory contains scripts and docs for connecting to Meta devservers.

All bash scripts in `meta/` run under WSL, not PowerShell. The one exception is `devterm.ps1`, which is a PowerShell script that launches Windows Terminal into WSL.

## What this repo is

Personal dotfiles and dev tooling. The `meta/` directory is a self-contained toolchain for SSH-ing into Meta devservers from a Windows/WSL setup. It bridges Windows' `fb-sks-agent` (Meta's SSH cert agent) into WSL via `npiperelay.exe` + `socat`, then uses native `ssh`.

## Architecture: SSH auth chain

```
WSL ssh → SSH_AUTH_SOCK (Unix socket) → socat → npiperelay.exe → Windows fb-sks-agent named pipe → Meta cert
```

The `.bashrc` starts the socat/npiperelay bridge on shell init. `~/.ssh/config` must `Include config-certs` for certificate auth.

## Key files in meta/

- **`devssh.sh`** — Core SSH connector. Hardcoded to `devvm7002.scu0.facebook.com`. Supports `-t` (tmux session "main") and `-t=<name>` (named tmux session). Uses `exec` so it replaces the shell process.
- **`tmux.sh`** — Interactive tmux session manager with arrow-key menu to list/attach/create/delete remote tmux sessions. Uses a single-SSH architecture: the menu script is base64-encoded locally, sent via SSH, decoded to a temp file on the devvm, and executed there. This avoids multiple SSH connections (and multiple Duo 2FA prompts). Supports `--test` for local testing with dummy data.
- **`devterm.ps1`** — PowerShell launcher. Finds an existing "devterm" Windows Terminal window and foregrounds it, or launches a new one into WSL running `tmux.sh`.
- **`CreateDevTerm.md`** — Setup guide for the Windows Start Menu shortcut that triggers `devterm.ps1`.
- **`TroubleshootingDevSSH.md`** — Diagnostic reference for SSH auth failures (npiperelay, interop, agent issues).

## Meta SSH constraints

- **Duo 2FA per connection**: Every SSH connection to the devvm requires a Duo prompt. SSH multiplexing (`ControlMaster`) does NOT work — the server refuses multiplexed sessions with `Session open refused by peer`. Design scripts to minimize the number of SSH connections.
- **Single-connection pattern**: To avoid multiple Duo prompts, `tmux.sh` runs everything in one SSH session. The menu script executes on the devvm where `tmux` commands are local (no nested SSH). This is the pattern to follow for any new interactive tooling.

## Terminal handling lessons (bash TUI)

These apply when building interactive menus in bash scripts that run over SSH:

- **Never use `$()` subshells for functions that do terminal I/O.** Subshells capture stdout, swallowing escape sequences and prompts. Use global variables (e.g., `KEY_RESULT`, `NEW_SESSION_NAME`) instead.
- **Use `read -rsN1`** (capital N), not `read -rsn1` (lowercase n). Lowercase `-n` treats `\n` as a delimiter and may swallow Enter keypresses. Capital `-N` reads exactly N bytes regardless.
- **Use `stty raw -echo`** for arrow key detection. Without it, each `read -rsN1` independently toggles terminal modes, and escape sequence bytes (`\x1b`, `[`, `A`) get lost between reads.
- **Match Enter by ASCII code**: Convert keys to ordinal (`printf '%d' "'$key"`) and match `10` (LF) or `13` (CR). Pattern matching with `$'\r'` in `case` statements is unreliable across environments.
- **Cursor positioning**: `\e[%dA` (cursor up) does NOT reset the column. Always append `\r` to return to column 0 after moving up, or the next render starts mid-line.
- **When the script runs remotely via SSH** (`bash script.sh`), read keyboard input from `/dev/tty` (fd 3 in tmux.sh) since stdin may not be the terminal. Use `[[ -t 3 ]]` to guard `stty` calls.

## Conventions

- Scripts share connection params (user `joepaley`, host `devvm7002.scu0.facebook.com`, `SSH_AUTH_SOCK` from the npiperelay bridge). When adding new scripts, replicate these rather than sourcing `devssh.sh` (which uses `exec`).
- The `bin/npiperelay.exe` is a Windows binary used from WSL via binfmt interop — it must remain a `.exe`.
- After modifying files in `meta/`, copy them to the WSL instance: use PowerShell (not Bash) to run `wsl` commands, since Git Bash mangles paths through its own filesystem.
