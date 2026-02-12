#!/bin/bash
# devssh - Connect to an On-Demand devserver from WSL2
# Uses dev.exe (Windows-side) to find running OD instances,
# then connects via Windows OpenSSH.

set -euo pipefail

SSH_EXE="/mnt/c/Windows/System32/OpenSSH/ssh.exe"
USER="joepaley"
TMUX_MODE=""
TMUX_SESSION="dev"
HOST_SELECT=""

usage() {
    cat <<EOF
Usage: devssh [OPTIONS]

Connect to an On-Demand devserver from WSL2.

Options:
  -t, --tmux [SESSION]   Attach to or create a tmux session (default: dev)
  -a, --attach [SESSION] Attach to existing tmux session (default: dev)
  -H, --host HOST        Specify host by index (1,2,...) or name (e.g., 28677.od)
  -h, --help             Show this help message

Examples:
  devssh                 Connect without tmux
  devssh -t              Connect and attach/create tmux session 'dev'
  devssh -t main         Connect and attach/create tmux session 'main'
  devssh -a              Attach to existing tmux session 'dev'
  devssh -a work         Attach to existing tmux session 'work'
  devssh -H 28677.od     Connect to specific host
  devssh -H 1            Connect to first host in list
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tmux)
            TMUX_MODE="new"
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                TMUX_SESSION="$2"
                shift
            fi
            shift
            ;;
        -a|--attach)
            TMUX_MODE="attach"
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                TMUX_SESSION="$2"
                shift
            fi
            shift
            ;;
        -H|--host)
            if [[ -z "${2:-}" || "$2" =~ ^- ]]; then
                echo "Error: -H requires a host argument" >&2
                exit 1
            fi
            HOST_SELECT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

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
elif [[ -n "$HOST_SELECT" ]]; then
    # Host specified via -H flag
    if [[ "$HOST_SELECT" =~ ^[0-9]+$ ]]; then
        # Numeric index
        if (( HOST_SELECT < 1 || HOST_SELECT > ${#hostnames[@]} )); then
            echo "Invalid host index: $HOST_SELECT (must be 1-${#hostnames[@]})" >&2
            exit 1
        fi
        host="${hostnames[$((HOST_SELECT - 1))]}"
    else
        # Host name - find matching hostname
        host=""
        for h in "${hostnames[@]}"; do
            if [[ "$h" == "$HOST_SELECT" || "$h" == "${HOST_SELECT}.od" ]]; then
                host="$h"
                break
            fi
        done
        if [[ -z "$host" ]]; then
            echo "Host not found: $HOST_SELECT" >&2
            echo "Available hosts:"
            for h in "${hostnames[@]}"; do
                echo "  - $h"
            done
            exit 1
        fi
    fi
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

case "$TMUX_MODE" in
    new)
        # tmux new-session -A -s <name>: attach if exists, create if not
        exec "$SSH_EXE" -t "${USER}@${host}.fbinfra.net" "tmux new-session -A -s ${TMUX_SESSION}"
        ;;
    attach)
        # tmux attach: attach to existing session only
        exec "$SSH_EXE" -t "${USER}@${host}.fbinfra.net" "tmux attach -t ${TMUX_SESSION}"
        ;;
    *)
        exec "$SSH_EXE" "${USER}@${host}.fbinfra.net"
        ;;
esac
