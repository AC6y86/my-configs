#!/bin/bash

# Mount Batocera server
BATOCERA_IP="192.168.1.205"
SHARE_NAME="share"  # Change this to your actual share name (e.g., "roms", "batocera")
MOUNT_POINT="/mnt/batocera"
USERNAME="root"
PASSWORD="linux"

# Create mount point if it doesn't exist
sudo mkdir -p "$MOUNT_POINT"

# Mount the share
echo "Mounting Batocera server at $BATOCERA_IP..."
sudo mount -t cifs "//$BATOCERA_IP/$SHARE_NAME" "$MOUNT_POINT" -o "username=$USERNAME,password=$PASSWORD,uid=$(id -u),gid=$(id -g),file_mode=0777,dir_mode=0777,iocharset=utf8"

# Check if mount was successful
if mountpoint -q "$MOUNT_POINT"; then
    echo "Successfully mounted Batocera at $MOUNT_POINT"
    ls "$MOUNT_POINT"
else
    echo "Failed to mount Batocera server"
    exit 1
fi