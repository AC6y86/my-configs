# CreateDevTerm

Create a Windows Start Menu shortcut called "devterm" that opens a new Windows Terminal with Ubuntu and SSHes into the Meta devserver with tmux.

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

- The shortcut runs `meta/devterm.ps1` which launches a new Windows Terminal (`wt -w new`, its own window) with the Ubuntu WSL profile and runs `tmux.sh` (the interactive tmux session manager)
- Searchable via Win key by typing "devterm"

## Per-session taskbar icons

Each devterm gets its own taskbar button + icon, keyed on the tmux session you
attach to. This is needed because all `wt.exe` windows are hosted by one
`WindowsTerminal.exe` process and otherwise share a single taskbar button.

- `devterm.ps1` starts `meta/devterm-tag-watcher.ps1` (hidden) before launching
  the window. `tmux.sh` sets the window title to `devterm: <session>` on attach;
  the watcher spots that window and overrides its property store with a
  per-session `System.AppUserModel.ID` + `RelaunchIconResource`, then briefly
  hides/re-shows it to force the shell to recreate the taskbar button (the shell
  only reads a window's AUMID at button-creation time).
- Icons are generated per session (colored initials, color hashed from the name)
  and cached in `%LOCALAPPDATA%\devterm\icons\`. Override a session by dropping
  `<session>.ico` in `windows/devterm-icons/` — see the README there.
- `meta/set-window-appid.ps1` is a standalone diagnostic for the same mechanism
  (`-List` dumps window titles; pass `-TitleMatch/-AppId/-IconPath -ForceRegroup`
  to tag a window by hand).
