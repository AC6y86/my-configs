#!/usr/bin/env sh

# LATEST VERSION OF THIS SCRIPT: https://gist.github.com/swayducky/8ba8f2db156c7f445d562cdc12c0ddb4
#   FORKED FROM: https://gist.github.com/ddwang/0046da801bcb29d241869d37ad719394
#     1) No longer has a hard-coded COMMIT
#     2) Auto-symlinks a "code" script to avoid wslCode.sh breaking

# HOW TO INSTALL:
#   1) Remove "c:\Users\<USER_NAME>\AppData\Local\Programs\cursor\resources\app\bin" from Windows Environment Settings
#   2) Modify this script with your Windows <USER_NAME> (NOT your WSL username) in the VSCODE_PATH variable
#   3) Save this script as ~/.local/bin/cursor
#   4) chmod +x ~/.local/bin/cursor

# See DISCUSSION:
#   Github Issue: https://github.com/getcursor/cursor/issues/807
#   Forum Thread: https://forum.cursor.com/t/is-there-wsl2-support/97/42

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.

if [ "$VSCODE_WSL_DEBUG_INFO" = true ]; then
	set -x
fi


SERVER_BIN="${HOME}/.cursor-server/bin/"
COMMIT="$(ls -t1 $SERVER_BIN 2> /dev/null | head -n 1)"  # dynamically figure out the COMMIT :)
APP_NAME="code"
QUALITY="stable"
NAME="Cursor"
SERVERDATAFOLDER=".cursor-server"
VSCODE_PATH="/home/joepaley/joepaley/AppData/Local/Programs/cursor"
ELECTRON="$VSCODE_PATH/$NAME.exe"

IN_WSL=false
if [ -n "$WSL_DISTRO_NAME" ]; then
	# $WSL_DISTRO_NAME is available since WSL builds 18362, also for WSL2
	IN_WSL=true
else
	WSL_BUILD=$(uname -r | sed -E 's/^[0-9.]+-([0-9]+)-Microsoft.*|.*/\1/')
	if [ -n "$WSL_BUILD" ]; then
		if [ "$WSL_BUILD" -ge 17063 ]; then
			# WSLPATH is available since WSL build 17046
			# WSLENV is available since WSL build 17063
			IN_WSL=true
		else
			# If running under older WSL, don't pass cli.js to Electron as
			# environment vars cannot be transferred from WSL to Windows
			# See: https://github.com/microsoft/BashOnWindows/issues/1363
			#      https://github.com/microsoft/BashOnWindows/issues/1494
			"$ELECTRON" "$@"
			exit $?
		fi
	fi
fi

if [ $IN_WSL = true ]; then
	export WSLENV="ELECTRON_RUN_AS_NODE/w:$WSLENV"
	CLI=$(wslpath -m "$VSCODE_PATH/resources/app/out/cli.js")

	# use the Remote WSL extension if installed
	WSL_EXT_ID="ms-vscode-remote.remote-wsl"

	ELECTRON_RUN_AS_NODE=1 "$ELECTRON" "$CLI" --ms-enable-electron-run-as-node --locate-extension $WSL_EXT_ID >/tmp/remote-wsl-loc.txt 2>/dev/null </dev/null
	WSL_EXT_WLOC=$(tail -n 1 /tmp/remote-wsl-loc.txt)
	WSL_CODE=$(wslpath -u "${WSL_EXT_WLOC%%[[:cntrl:]]}")/scripts/wslCode.sh

    MY_CLI_DIR_YO="$SERVER_BIN/$COMMIT/bin/remote-cli"
    
    # if /code doesn't exist, symlink it
    if [ ! -e "$MY_CLI_DIR_YO/code" ]; then
        ln -s "$MY_CLI_DIR_YO/cursor" "$MY_CLI_DIR_YO/code"
    fi

	if [ -n "$WSL_EXT_WLOC" ]; then
		# replace \r\n with \n in WSL_EXT_WLOC
		WSL_CODE=$(wslpath -u "${WSL_EXT_WLOC%%[[:cntrl:]]}")/scripts/wslCode.sh
		"$WSL_CODE" "$COMMIT" "$QUALITY" "$ELECTRON" "$APP_NAME" "$SERVERDATAFOLDER" "$@"
		exit $?
	fi

elif [ -x "$(command -v cygpath)" ]; then
	CLI=$(cygpath -m "$VSCODE_PATH/resources/app/out/cli.js")
else
	CLI="$VSCODE_PATH/resources/app/out/cli.js"
fi
ELECTRON_RUN_AS_NODE=1 "$ELECTRON" "$CLI" --ms-enable-electron-run-as-node "$@"
exit $?