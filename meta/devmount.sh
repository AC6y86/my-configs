#!/bin/bash
set -euo pipefail

MOUNT_POINT="/Volumes/devserver"
USER="joepaley"
HOST="devvm7002.scu0.facebook.com"
REMOTE_PATH="/data/users/$USER"
FB_SKS_SOCK="$HOME/.fb-sks-agent/agent.sock"

setup_ssh_auth() {
    if [[ -S "$FB_SKS_SOCK" ]]; then
        export SSH_AUTH_SOCK="$FB_SKS_SOCK"
    elif [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        echo "ERROR: No fb-sks-agent socket and SSH_AUTH_SOCK not set." >&2
        echo "Try: /opt/facebook/bin/fb-sks-agent restart" >&2
        exit 1
    fi
}

do_mount() {
    if mount | grep -q "$MOUNT_POINT"; then
        if [[ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]]; then
            echo "Already mounted at $MOUNT_POINT"
            exit 0
        else
            echo "Stale mount detected at $MOUNT_POINT, unmounting..."
            umount "$MOUNT_POINT" 2>/dev/null || diskutil unmount force "$MOUNT_POINT" 2>/dev/null
            sleep 1
        fi
    fi

    if ! command -v sshfs &>/dev/null; then
        echo "ERROR: sshfs not found. Install it from https://macfuse.github.io/" >&2
        exit 1
    fi

    setup_ssh_auth
    if [[ ! -d "$MOUNT_POINT" ]]; then
        echo "Creating mount point (requires sudo)..."
        sudo mkdir -p "$MOUNT_POINT"
    fi
    echo "Mounting ${USER}@${HOST}:${REMOTE_PATH} → ${MOUNT_POINT}"
    sshfs -o backend=fskit -o IdentityAgent="$SSH_AUTH_SOCK" \
        "${USER}@${HOST}:${REMOTE_PATH}" "$MOUNT_POINT"

    if mount | grep -q "$MOUNT_POINT" && [[ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]]; then
        echo "Mounted successfully."
    else
        echo "WARNING: Mount command completed but no files visible at $MOUNT_POINT" >&2
        echo "Try: umount $MOUNT_POINT && $0 mount" >&2
        exit 1
    fi
}

do_unmount() {
    if ! mount | grep -q "$MOUNT_POINT"; then
        echo "Nothing mounted at $MOUNT_POINT"
        exit 0
    fi
    umount "$MOUNT_POINT"
    echo "Unmounted $MOUNT_POINT"
}

do_status() {
    if mount | grep -q "$MOUNT_POINT"; then
        echo "Mounted: $(mount | grep "$MOUNT_POINT")"
    else
        echo "Not mounted"
    fi
}

case "${1:-mount}" in
    mount)   do_mount ;;
    unmount) do_unmount ;;
    status)  do_status ;;
    *)
        echo "Usage: $(basename "$0") [mount|unmount|status]" >&2
        exit 1
        ;;
esac
