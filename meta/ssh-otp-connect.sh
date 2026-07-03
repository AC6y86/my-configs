#!/bin/bash
# ssh-otp-connect.sh -- YubiKey type-ahead wrapper around `ssh`.
#
# Every SSH connection to the Meta devvm ends in a Duo 2FA prompt, answered by
# pressing a YubiKey (which emits a ~44-char Yubico OTP). Normally you must wait
# for the connection to reach that prompt before you can press the key. This
# wrapper lets you press it *immediately at launch*, overlapping the SSH
# handshake: a background reader captures the OTP up front, and an askpass helper
# hands it to ssh the moment the Duo prompt fires.
#
# Yubico OTPs are counter-based (valid until the next OTP from that key is used),
# not time-based, so pre-generating one a few seconds early is safe.
#
# Usage: exec ssh-otp-connect.sh <all the normal ssh args...>
# It forwards every arg to ssh verbatim via "$@" (never eval/$*), so a single
# complex remote-command arg (e.g. tmux.sh's base64 payload) passes through
# untouched.
#
# Mechanism: OpenSSH >= 8.4 routes keyboard-interactive prompts (what Duo uses)
# to $SSH_ASKPASS when SSH_ASKPASS_REQUIRE=force, with no $DISPLAY needed.
#
# Kill switch: DEVSSH_NO_OTP=1 (or no controlling tty) -> plain `exec ssh "$@"`,
# i.e. the old manual-prompt behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASKPASS="$SCRIPT_DIR/otp-askpass.sh"

# Bail out to plain ssh if disabled, if we have no tty to read the key from, or
# if the askpass helper is missing. This keeps every failure mode == old behavior.
if [[ "${DEVSSH_NO_OTP:-}" == "1" ]] || [[ ! -r /dev/tty ]] || [[ ! -x "$ASKPASS" ]]; then
    exec ssh "$@"
fi

# Single-line OTP scratch file, private, on tmpfs where available. Sweep any
# leftovers from runs that died before their OTP was consumed (see below).
OTP_DIR="${XDG_RUNTIME_DIR:-/tmp}"
find "$OTP_DIR" -maxdepth 1 -name '.devssh_otp.*' -mmin +5 -delete 2>/dev/null || true
OTP_FILE="$(mktemp "$OTP_DIR/.devssh_otp.XXXXXX")"
chmod 600 "$OTP_FILE" 2>/dev/null || true

# Background read-ahead: prompt on the tty and capture one line (the YubiKey
# types the OTP + Enter). Exits as soon as it has the line, releasing the tty
# before the post-auth interactive session starts. On exit it unlinks the
# scratch file ONLY if still empty (user skipped, or the reader was killed before
# capturing) -- a captured OTP is left for otp-askpass.sh to consume and unlink.
# The trap is valid because this subshell is NOT replaced by exec.
(
    trap '[[ -s "$OTP_FILE" ]] || rm -f "$OTP_FILE"' EXIT
    printf '\r\033[2m🔑 Touch YubiKey (or Enter to skip)…\033[0m ' > /dev/tty
    otp=""
    IFS= read -rs otp < /dev/tty || true
    printf '\r\n' > /dev/tty
    printf '%s' "$otp" > "$OTP_FILE"
) &
READER_PID=$!

export SSH_ASKPASS="$ASKPASS"
export SSH_ASKPASS_REQUIRE="force"
export DEVSSH_OTP_FILE="$OTP_FILE"
export DEVSSH_OTP_READER_PID="$READER_PID"

exec ssh "$@"
