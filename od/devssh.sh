#!/bin/bash
# devssh - Connect to dev servers from WSL2
# Uses dev.exe (Windows-side) to find running OD instances and persistent devservers,
# then connects via Windows OpenSSH.

set -euo pipefail

SSH_EXE="/mnt/c/Windows/System32/OpenSSH/ssh.exe"
USER="joepaley"
DEDICATED_HOST="devvm38239.prn0"
TMUX_MODE=""
TMUX_SESSION="dev"
HOST_SELECT=""
LIST_MODE=false
CLAW_MODE=false

usage() {
    cat <<EOF
Usage: devssh [OPTIONS]

Connect to dev servers (On-Demand or persistent devservers) from WSL2.
Default: connects to an available OD instance

Options:
  -c, --claw             Connect to dedicated server (devvm38239.prn0) for myclaw
  -t, --tmux [SESSION]   Attach to or create a tmux session (default: dev)
  -a, --attach [SESSION] Attach to existing tmux session (default: dev)
  -H, --host HOST        Specify host by index (1,2,...) or name (e.g., 28677.od, devvm123.prn0)
  -l, --list             List and select from all available dev servers
  -h, --help             Show this help message

Examples:
  devssh                 Connect to an available OD instance
  devssh -c              Connect to dedicated server for myclaw
  devssh -t              Connect to OD instance with tmux session 'dev'
  devssh -l              List and select from all available servers
  devssh -H 28677.od     Connect to specific OD host
  devssh -H devvm123.prn0  Connect to specific persistent devserver
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--claw)
            CLAW_MODE=true
            shift
            ;;
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
        -l|--list)
            LIST_MODE=true
            shift
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

# Handle claw mode (dedicated server)
if [[ "$CLAW_MODE" == true ]]; then
    host="$DEDICATED_HOST"
# Use OD instance by default unless -l or -H is specified
elif [[ "$LIST_MODE" == false ]] && [[ -z "$HOST_SELECT" ]]; then
    # Check that dev.exe is available
    if ! command -v dev.exe &>/dev/null; then
        echo "Error: dev.exe not found in PATH." >&2
        echo "Make sure the Meta Dev CLI is installed on the Windows side." >&2
        exit 1
    fi

    # Get list of running dev servers (OD and persistent)
    output="$(dev.exe list 2>&1)" || true

    # Extract hostnames (OD instances like "68883.od" or persistent like "devvm123.prn0")
    mapfile -t hostnames < <(echo "$output" | grep -oP '^[^\s(]+\.[^\s(]+' | sort -u)

    if [[ ${#hostnames[@]} -eq 0 ]]; then
        echo "No dev servers found."
        read -rp "Create an OD instance? (y/n) " answer
        if [[ "$answer" =~ ^[Yy] ]]; then
            exec dev.exe connect
        else
            exit 0
        fi
    fi

    # Use first available OD instance by default
    host="${hostnames[0]}"
else
    # Check that dev.exe is available
    if ! command -v dev.exe &>/dev/null; then
        echo "Error: dev.exe not found in PATH." >&2
        echo "Make sure the Meta Dev CLI is installed on the Windows side." >&2
        exit 1
    fi

    # Get list of running dev servers (OD and persistent)
    output="$(dev.exe list 2>&1)" || true

    # Extract hostnames (OD instances like "68883.od" or persistent like "devvm123.prn0")
    mapfile -t hostnames < <(echo "$output" | grep -oP '^[^\s(]+\.[^\s(]+' | sort -u)

    if [[ ${#hostnames[@]} -eq 0 ]]; then
        echo "No dev servers found."
        read -rp "Create an OD instance? (y/n) " answer
        if [[ "$answer" =~ ^[Yy] ]]; then
            exec dev.exe connect
        else
            exit 0
        fi
    fi

    if [[ ${#hostnames[@]} -eq 1 ]] && [[ -z "$HOST_SELECT" ]]; then
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
                # Try exact match or partial match (e.g., "28677" matches "28677.od")
                if [[ "$h" == "$HOST_SELECT" ]] || \
                   [[ "$h" == "${HOST_SELECT}.od" ]] || \
                   [[ "$h" =~ ^devvm${HOST_SELECT}\. ]]; then
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
        echo "Multiple dev servers found:"
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
