#!/bin/bash
set -euo pipefail

if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "ERROR: SSH_AUTH_SOCK not set. Run 'source ~/.bashrc' or open a new terminal." >&2
    echo "If this is a new machine, see ~/my-configs/meta/CreateDevTerm.md for setup." >&2
    exit 1
fi
SSH_EXE="ssh"
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

echo "Connecting to ${HOST} ..."
if [[ -n "$TMUX_SESSION" ]]; then
    exec "$SSH_EXE" "${SSH_OPTS[@]}" "${USER}@${HOST}" -t "tmux new-session -A -s ${TMUX_SESSION}"
else
    exec "$SSH_EXE" "${SSH_OPTS[@]}" "${USER}@${HOST}"
fi