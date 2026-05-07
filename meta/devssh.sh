#!/bin/bash
set -euo pipefail

SSH_EXE="/mnt/c/Windows/System32/OpenSSH/ssh.exe"
USER="joepaley"
HOST="devvm7002.scu0.facebook.com"

echo "Connecting to ${HOST} ..."
exec "$SSH_EXE" "${USER}@${HOST}"