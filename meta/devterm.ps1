# Launch a new Windows Terminal running the tmux session menu (tmux.sh), and
# start a hidden watcher that gives the window its own taskbar button + icon once
# it attaches to a session. See devterm-tag-watcher.ps1 for the why.

# Start the watcher first so it snapshots existing devterm windows before this
# one attaches to a session.
$watcher = Join-Path $PSScriptRoot "devterm-tag-watcher.ps1"
Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $watcher
) | Out-Null

# -w new forces a brand-new window (not a tab in an existing one) so each devterm
# is its own top-level window and can carry its own taskbar identity.
& wt.exe -w new --title devterm -p Ubuntu -d "\\wsl$\Ubuntu\home\joepaley" -- bash -l -c "~/my-configs/meta/tmux.sh"
