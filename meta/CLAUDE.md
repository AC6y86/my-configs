# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Environment

The `meta/` subdirectory is a self-contained toolchain for SSH-ing into Meta devservers, and it runs on **WSL2 (Ubuntu), macOS, and native Linux**. On WSL the repo lives at `C:\Users\joepaley\my-configs` (Windows) and is mapped into WSL at `~/my-configs`; on macOS/Linux it is checked out directly under `~/my-configs`.

The bash scripts (`devssh.sh`, `tmux.sh`, `devmount.sh`) run under bash on any of those platforms — they detect the OS to locate the SSH cert agent. `tmux.sh` is deliberately written to parse under macOS's system bash 3.2 (no heredoc-in-`$()`). PowerShell is involved only on Windows: `devterm.ps1` launches Windows Terminal into WSL running `tmux.sh`.

## What this repo is

Personal dotfiles and dev tooling. The `meta/` directory uses Meta's `fb-sks-agent` (the SSH cert agent) to authenticate native `ssh`. How that agent is reached depends on the platform:

- **WSL**: the Windows `fb-sks-agent` named pipe is bridged into a WSL Unix socket via `npiperelay.exe` + `socat` (started by `.bashrc`).
- **macOS / native Linux**: `fb-sks-agent` runs natively, exposing `~/.fb-sks-agent/agent.sock` directly — no bridge.

## Architecture: SSH auth chain

```
WSL:           ssh → SSH_AUTH_SOCK (Unix socket) → socat → npiperelay.exe → Windows fb-sks-agent named pipe → Meta cert
macOS / Linux: ssh → SSH_AUTH_SOCK = ~/.fb-sks-agent/agent.sock → native fb-sks-agent → Meta cert
```

On WSL, `.bashrc` starts the socat/npiperelay bridge on shell init. On macOS/Linux the scripts point `SSH_AUTH_SOCK` at the native socket themselves. In all cases `~/.ssh/config` must `Include config-certs` for certificate auth.

## Key files in meta/

- **`devssh.sh`** — Core SSH connector. Hardcoded to `devvm7002.scu0.facebook.com`. Supports `-t` (tmux session "main") and `-t=<name>` (named tmux session). Uses `exec` so it replaces the shell process.
- **`tmux.sh`** — Interactive tmux session manager with arrow-key menu to list/attach/create/delete remote tmux sessions. Cross-platform: it resolves the SSH cert agent itself (prefers the native `~/.fb-sks-agent/agent.sock`, else the env's `SSH_AUTH_SOCK` from the WSL bridge). Uses a single-SSH architecture: the menu script is sent via SSH and executed on the devvm. This avoids multiple SSH connections (and multiple Duo 2FA prompts). Supports `--test` for local testing with dummy data.
- **`devmount.sh`** — macOS only. sshfs-mounts the devserver home (`/data/users/joepaley`) at `/Volumes/devserver`. Subcommands `mount` (default) / `unmount` / `status`. Requires macFUSE/sshfs; resolves the native `fb-sks-agent` socket.
- **`devterm.ps1`** — PowerShell launcher (Windows). Opens a "devterm" Windows Terminal window into WSL running `tmux.sh`.
- **`CreateDevTerm.md`** — Setup guide for the Windows Start Menu shortcut that triggers `devterm.ps1`.
- **`CreateDevTerm-mac.md`** — macOS equivalent: builds a Spotlight-searchable `DevTerm.app` that opens iTerm2 into `tmux.sh`.
- **`CreateDevTerm-linux.md`** — native Linux / GNOME equivalent: writes a searchable `devterm.desktop` entry that opens ptyxis into `tmux.sh`.
- **`TroubleshootingDevSSH.md`** — Diagnostic reference for SSH auth failures (npiperelay/bridge on WSL, native agent on macOS/Linux, interop, agent issues).
- **`ssh-otp-connect.sh`** / **`otp-askpass.sh`** — YubiKey type-ahead for the Duo prompt (see "Duo YubiKey type-ahead" below). Both `devssh.sh` and `tmux.sh` `exec` into `ssh-otp-connect.sh` instead of `ssh` directly.

## Meta SSH constraints

- **Duo 2FA per connection**: Every SSH connection to the devvm requires a Duo prompt. SSH multiplexing (`ControlMaster`) does NOT work — the server refuses multiplexed sessions with `Session open refused by peer`. Design scripts to minimize the number of SSH connections.
- **Single-connection pattern**: To avoid multiple Duo prompts, `tmux.sh` runs everything in one SSH session. The menu script executes on the devvm where `tmux` commands are local (no nested SSH). This is the pattern to follow for any new interactive tooling.

## Duo YubiKey type-ahead

The Duo answer is a **Yubico OTP** (the YubiKey emits a ~44-char modhex passcode; counter-based, so valid until the next OTP from that key is used — not time-limited). To avoid the serial "wait for the prompt, *then* touch" round-trip, `devssh.sh`/`tmux.sh` route through **`ssh-otp-connect.sh`**, which lets you press the YubiKey *at launch*, overlapping the SSH handshake:

- The wrapper starts a **background reader** that prompts on `/dev/tty` and captures the OTP into a private scratch file under `$XDG_RUNTIME_DIR`, then `exec`s `ssh` with `SSH_ASKPASS=otp-askpass.sh` and `SSH_ASKPASS_REQUIRE=force`.
- OpenSSH ≥ 8.4 routes **keyboard-interactive** prompts (what Duo uses) to `SSH_ASKPASS` under `force`, with no `$DISPLAY` needed. `otp-askpass.sh` returns the captured OTP for the passcode prompt (waiting on the file if the handshake wins the race), consuming it once so an auth retry can't resubmit a spent code.
- **Exactly one process reads `/dev/tty` at a time** (the reader, or askpass) — critical so the reader releases the tty before `tmux.sh`'s post-auth arrow-key menu starts.
- **Every failure degrades to the normal manual Duo prompt**: no tty, unreadable OTP, retry, a non-passcode prompt (e.g. cert passphrase), or the kill switch. Disable entirely with **`DEVSSH_NO_OTP=1`**.
- Uses `SSH_ASKPASS`, not `expect` (not installed). Primarily validated on Linux; the mechanism is the same on macOS/WSL but untested there.

## Terminal handling lessons (bash TUI)

These apply when building interactive menus in bash scripts that run over SSH:

- **Never use `$()` subshells for functions that do terminal I/O.** Subshells capture stdout, swallowing escape sequences and prompts. Use global variables (e.g., `KEY_RESULT`, `NEW_SESSION_NAME`) instead.
- **Use `read -rsN1`** (capital N), not `read -rsn1` (lowercase n). Lowercase `-n` treats `\n` as a delimiter and may swallow Enter keypresses. Capital `-N` reads exactly N bytes regardless.
- **Use `stty raw -echo`** for arrow key detection. Without it, each `read -rsN1` independently toggles terminal modes, and escape sequence bytes (`\x1b`, `[`, `A`) get lost between reads.
- **Match Enter by ASCII code**: Convert keys to ordinal (`printf '%d' "'$key"`) and match `10` (LF) or `13` (CR). Pattern matching with `$'\r'` in `case` statements is unreliable across environments.
- **Cursor positioning**: `\e[%dA` (cursor up) does NOT reset the column. Always append `\r` to return to column 0 after moving up, or the next render starts mid-line.
- **When the script runs remotely via SSH** (`bash script.sh`), read keyboard input from `/dev/tty` (fd 3 in tmux.sh) since stdin may not be the terminal. Use `[[ -t 3 ]]` to guard `stty` calls.

## Conventions

- Scripts share connection params (user `joepaley`, host `devvm7002.scu0.facebook.com`). Resolve `SSH_AUTH_SOCK` the cross-platform way (prefer native `~/.fb-sks-agent/agent.sock`, else the env's value from the WSL bridge) — see `tmux.sh`/`devmount.sh` for the pattern. When adding new scripts, replicate these rather than sourcing `devssh.sh` (which uses `exec`).
- Keep new bash scripts portable across WSL, macOS, and Linux. Watch for macOS's system bash 3.2 (no associative-array/heredoc-in-`$()` features) and macOS BSD vs. GNU tool differences.
- `bin/npiperelay.exe` (WSL only) is a Windows binary used from WSL via binfmt interop — it must remain a `.exe`. It is unused on macOS/Linux.
- On macOS/Linux the repo is checked out directly, so edits take effect in place. On WSL only: if you edit the Windows-side copy, sync it into the WSL filesystem — use PowerShell (not Git Bash) to run `wsl` commands, since Git Bash mangles paths.
