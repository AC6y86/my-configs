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
- **`tmux.sh`** — Interactive tmux session manager. Wraps `devssh.sh`. Arrow-key menu to list/attach/create/delete remote tmux sessions. Calls `devssh.sh -t=<name>` for the final connection.
- **`devterm.ps1`** — PowerShell launcher. Finds an existing "devterm" Windows Terminal window and foregrounds it, or launches a new one into WSL running `devssh.sh -t`.
- **`CreateDevTerm.md`** — Setup guide for the Windows Start Menu shortcut that triggers `devterm.ps1`.
- **`TroubleshootingDevSSH.md`** — Diagnostic reference for SSH auth failures (npiperelay, interop, agent issues).

## Conventions

- Scripts share connection params (user `joepaley`, host `devvm7002.scu0.facebook.com`, `SSH_AUTH_SOCK` from the npiperelay bridge). When adding new scripts, replicate these rather than sourcing `devssh.sh` (which uses `exec`).
- The `bin/npiperelay.exe` is a Windows binary used from WSL via binfmt interop — it must remain a `.exe`.
