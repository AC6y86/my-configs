# CreateDevTerm (macOS)

Create a Spotlight-searchable "DevTerm" app that opens iTerm2 and SSHes into the
Meta devserver with tmux. macOS equivalent of the Windows Start Menu shortcut
(see `CreateDevTerm.md`).

## Prerequisites

No SSH agent bridge needed (unlike WSL). On macOS, `fb-sks-agent` runs natively and
`tmux.sh` points `SSH_AUTH_SOCK` at `~/.fb-sks-agent/agent.sock` itself. If auth
fails, run `/opt/facebook/bin/fb-sks-agent restart`.

## Setup

Run this in a terminal to build a minimal `.app` bundle in `~/Applications`.
Spotlight indexes `~/Applications`, so ⌘Space → "devterm" will find it:

```bash
APP="$HOME/Applications/DevTerm.app"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>DevTerm</string>
  <key>CFBundleDisplayName</key>     <string>DevTerm</string>
  <key>CFBundleIdentifier</key>      <string>com.joepaley.devterm</string>
  <key>CFBundleExecutable</key>      <string>devterm</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/MacOS/devterm" <<'SH'
#!/bin/bash
# Open a new iTerm2 window running the tmux session manager, then foreground it.
osascript <<'OSA'
tell application "iTerm"
  create window with default profile command "/bin/bash -lc '~/my-configs/meta/tmux.sh'"
  activate
end tell
OSA
SH

chmod +x "$APP/Contents/MacOS/devterm"
```

## How it works

- The `.app`'s executable runs `osascript`, which tells iTerm2 to create a new
  window whose command is `tmux.sh` (the interactive tmux session manager), then
  foregrounds iTerm2.
- Searchable via ⌘Space by typing "devterm".
- To change behavior, edit `~/Applications/DevTerm.app/Contents/MacOS/devterm`.

## Notes

- First launch: macOS may prompt to allow DevTerm to control iTerm via Apple
  Events — approve it (System Settings → Privacy & Security → Automation).
- The window closes when `tmux.sh` exits, per iTerm2's default profile setting
  "When the session ends". Set the profile to keep it open if you prefer.
