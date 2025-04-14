#!/bin/bash
CURRENT_PATH=$(readlink -f "$1")

# Get the default WSL distro name (clean nulls and carriage returns)
DEFAULT_DISTRO=$(wsl.exe -l --verbose | tr -d '\0' | awk '/\*/ {print $2}' | tr -d '\r')

windsurf --folder-uri "vscode-remote://wsl+${DEFAULT_DISTRO}${CURRENT_PATH}"
