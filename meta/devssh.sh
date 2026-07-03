#!/bin/bash
set -euo pipefail

if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "ERROR: SSH_AUTH_SOCK not set. Run 'source ~/.bashrc' or open a new terminal." >&2
    echo "If this is a new machine, see ~/my-configs/meta/CreateDevTerm.md for setup." >&2
    exit 1
fi
SSH_OPTS=(-o "IdentityAgent=$SSH_AUTH_SOCK")
USER="joepaley"
HOST="devvm7002.scu0.facebook.com"
TMUX_SESSION=""

for arg in "$@"; do
    case "$arg" in
        -t) TMUX_SESSION="main" ;;
        -t=*) TMUX_SESSION="${arg#-t=}" ;;
        *) echo "Usage: devssh [-t [session_name]]" >&2; exit 1 ;;
    esac
done

# Route through the YubiKey type-ahead wrapper (falls back to plain ssh when
# disabled via DEVSSH_NO_OTP=1 or when there's no tty). See ssh-otp-connect.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT="$SCRIPT_DIR/ssh-otp-connect.sh"

echo "Connecting to ${HOST} ..."
if [[ -n "$TMUX_SESSION" ]]; then
    exec "$CONNECT" "${SSH_OPTS[@]}" "${USER}@${HOST}" -t "tmux new-session -A -s ${TMUX_SESSION}"
else
    exec "$CONNECT" "${SSH_OPTS[@]}" "${USER}@${HOST}"
fi