#!/bin/bash
DEST=~/joepaley/.ssh
mkdir -p "$DEST"
cp -f ~/.ssh/* "$DEST"
echo "SSH files synced to $DEST"