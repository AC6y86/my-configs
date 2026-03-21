#!/bin/bash

USER="openclaw"
HOST="100.123.210.124"
SSH_ARGS=""

usage() {
    echo "Usage: ssh_claw.sh [OPTIONS]"
    echo ""
    echo "SSH into OpenClaw machine."
    echo ""
    echo "Options:"
    echo "  -r, --root    SSH as root instead of openclaw"
    echo "  -b            SSH to browser VM with port forwarding (6080)"
    echo "  -h, --help    Show this help message"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--root)
            USER="root"
            shift
            ;;
        -b)
            HOST="100.123.210.124"
            SSH_ARGS="-N -L 6080:localhost:6080"
            echo "noVNC available at http://localhost:6080/vnc.html"
            echo "Press Ctrl+C to exit"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

ssh $SSH_ARGS "${USER}@${HOST}"
