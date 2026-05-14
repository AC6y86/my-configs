# CreateDevTerm

Create a Windows Start Menu shortcut called "devterm" that opens a new Windows Terminal with Ubuntu and SSHes into the Meta devserver with tmux. If a devterm window is already open, it brings it to the foreground instead.

## Prerequisites

The SSH agent bridge must be set up (done via `.bashrc`):
- `npiperelay.exe` in `~/my-configs/bin/` bridges the Windows `fb-sks-agent` Named Pipe to a Unix socket
- `socat` starts the bridge on shell init, setting `SSH_AUTH_SOCK`
- This allows WSL's native `ssh` to authenticate through Meta's fb-sks-agent

## Setup

Run this in PowerShell to create the Start Menu shortcut:

```powershell
$shell = New-Object -ComObject WScript.Shell
$shortcutPath = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\devterm.lnk')
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = '-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Users\joepaley\my-configs\meta\devterm.ps1"'
$shortcut.WindowStyle = 7
$shortcut.Save()
```

## How it works

- The shortcut runs `meta/devterm.ps1` which checks for an existing Terminal window with "ssh" in the title
- If found, it brings that window to the foreground (restoring it if minimized)
- If not found, it launches a new Windows Terminal with the Ubuntu WSL profile and runs `devssh.sh -t`
- Searchable via Win key by typing "devterm"
