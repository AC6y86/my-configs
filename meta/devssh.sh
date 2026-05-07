#!/bin/bash
set -euo pipefail

SSH_EXE="/mnt/c/Windows/System32/OpenSSH/ssh.exe"
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
    exec "$SSH_EXE" "${USER}@${HOST}" -t "tmux new-session -A -s ${TMUX_SESSION}"
else
    exec "$SSH_EXE" "${USER}@${HOST}"
fi