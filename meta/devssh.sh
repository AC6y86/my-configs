#!/bin/bash
# devssh - Connect to an On-Demand devserver from WSL2
# Uses dev.exe (Windows-side) to find running OD instances,
# then connects via Windows OpenSSH.

set -euo pipefail

SSH_EXE="/mnt/c/Windows/System32/OpenSSH/ssh.exe"
USER="joepaley"

# Check that dev.exe is available
if ! command -v dev.exe &>/dev/null; then
    echo "Error: dev.exe not found in PATH." >&2
    echo "Make sure the Meta Dev CLI is installed on the Windows side." >&2
    exit 1
fi

# Get list of running OD instances
output="$(dev.exe list 2>&1)" || true

# Extract OD hostnames (patterns like "68883.od" at start of table rows)
mapfile -t hostnames < <(echo "$output" | grep -oP '^\S*[0-9]+\.od\b' | sort -u)

if [[ ${#hostnames[@]} -eq 0 ]]; then
    echo "No OD instances found."
    read -rp "Create one? (y/n) " answer
    if [[ "$answer" =~ ^[Yy] ]]; then
        exec dev.exe connect
    else
        exit 0
    fi
fi

if [[ ${#hostnames[@]} -eq 1 ]]; then
    host="${hostnames[0]}"
else
    echo "Multiple OD instances found:"
    for i in "${!hostnames[@]}"; do
        echo "  $((i + 1)). ${hostnames[$i]}.fbinfra.net"
    done
    read -rp "Pick one [1-${#hostnames[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#hostnames[@]} )); then
        echo "Invalid selection." >&2
        exit 1
    fi
    host="${hostnames[$((choice - 1))]}"
fi

echo "Connecting to ${host}.fbinfra.net ..."
exec "$SSH_EXE" "${USER}@${host}.fbinfra.net"