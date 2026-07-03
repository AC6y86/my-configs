#!/bin/bash
# otp-askpass.sh -- SSH_ASKPASS helper for ssh-otp-connect.sh.
#
# ssh invokes this once per auth prompt, passing the prompt text as $1. For a Duo
# passcode prompt we return the YubiKey OTP captured up front by the wrapper's
# background reader (consumed exactly once). For anything else -- a cert
# passphrase, an auth-retry after a bad OTP, or if no OTP was captured -- we fall
# back to a normal interactive read from /dev/tty, so the user is never locked
# out (worst case they just answer Duo the old way).
set -u

PROMPT="${1:-}"
OTP_FILE="${DEVSSH_OTP_FILE:-}"
POLL_MAX=20   # ~10s at 0.5s steps: bound the wait so a hung reader can't wedge auth.

# Answer the prompt by reading from the terminal directly (echo off).
interactive() {
    local ans=""
    # Open the terminal directly; if there's no controlling tty (open fails with
    # ENXIO even when the node is readable), just return empty and let ssh show
    # its own prompt / fail normally.
    if { printf '%s' "$PROMPT" > /dev/tty; } 2>/dev/null; then
        IFS= read -rs ans < /dev/tty 2>/dev/null || true
        printf '\r\n' > /dev/tty 2>/dev/null || true
    fi
    printf '%s\n' "$ans"
    exit 0
}

# Only auto-fill Duo passcode-style prompts; pass everything else to the user.
shopt -s nocasematch
case "$PROMPT" in
    *passcode*|*duo*|*option*) : ;;
    *) interactive ;;
esac
shopt -u nocasematch

[[ -n "$OTP_FILE" ]] || interactive

# Wait for the background reader to deliver a non-empty OTP. This covers the race
# where the SSH handshake reaches auth before the user has touched the key. Only
# ONE process reads /dev/tty at a time: while the reader owns it, we just poll
# the file here rather than opening our own read.
tries=0
while [[ ! -s "$OTP_FILE" ]]; do
    # Reader gone with nothing captured -> user skipped (pressed Enter) or the
    # reader died: hand off to a manual prompt.
    if [[ -n "${DEVSSH_OTP_READER_PID:-}" ]] && ! kill -0 "$DEVSSH_OTP_READER_PID" 2>/dev/null; then
        interactive
    fi
    tries=$((tries + 1))
    [[ $tries -ge $POLL_MAX ]] && interactive
    sleep 0.5
done

# Consume once: read then unlink so an auth retry can't resubmit a spent OTP.
otp="$(cat "$OTP_FILE" 2>/dev/null || true)"
rm -f "$OTP_FILE"

# Sanity-check it looks like a Yubico OTP (modhex, ~44 chars) before submitting.
if [[ "$otp" =~ ^[cbdefghijklnrtuv]{32,48}$ ]]; then
    printf '%s\n' "$otp"
    exit 0
fi
interactive
