#!/bin/bash
CURRENT_PATH=$(readlink -f "$1")
windsurf --folder-uri "vscode-remote://wsl+Ubuntu$CURRENT_PATH"
