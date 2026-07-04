# CreateDevTerm (native Linux / GNOME)

Create a GNOME-searchable "DevTerm" launcher that opens a new ptyxis terminal and
SSHes into the Meta devserver with tmux. Native-Linux equivalent of the Windows
Start Menu shortcut (`CreateDevTerm.md`) and the macOS app (`CreateDevTerm-mac.md`).

## Prerequisites

No SSH agent bridge needed (unlike WSL). On native Linux, `fb-sks-agent` runs
natively and `tmux.sh` points `SSH_AUTH_SOCK` at `~/.fb-sks-agent/agent.sock`
itself. If auth fails, restart the agent (`/opt/facebook/bin/fb-sks-agent restart`,
or the systemd unit if it is managed that way).

Assumes GNOME with **ptyxis** (Fedora's default terminal) installed.

## Setup

Run this in a terminal to write a freedesktop `.desktop` entry. GNOME indexes
`~/.local/share/applications`, so Super → "devterm" will find it:

```bash
cat > "$HOME/.local/share/applications/devterm.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=DevTerm
Comment=SSH into the Meta devserver with tmux
Exec=ptyxis --new-window -- bash -lc "/home/joepaley/my-configs/meta/tmux.sh"
Icon=utilities-terminal
Terminal=false
Categories=Development;
Keywords=devterm;tmux;meta;ssh;devvm;
DESKTOP

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
```

## How it works

- The `.desktop` entry runs `ptyxis --new-window -- bash -lc "/home/joepaley/my-configs/meta/tmux.sh"`,
  opening a terminal whose command is `tmux.sh` (the interactive tmux session manager).
- **`--new-window`** makes each launch open a fresh terminal window. ptyxis is a
  single-instance app, so the new window lives in the existing ptyxis process; if
  you want a fully separate instance every time, swap `--new-window` for
  `-s`/`--standalone`.
- **`Terminal=false`** — ptyxis supplies its own window, so GNOME must not wrap it
  in a second terminal.
- `bash -lc` runs a login shell so the full `PATH`/environment is set up before
  `tmux.sh` runs. The freedesktop `Exec` spec reserves `~` and `'`, so the path is
  spelled out absolutely and quoted with double quotes (run
  `desktop-file-validate` after editing to confirm it stays legal).
- Searchable via the GNOME Super key by typing "devterm".
- To change behavior, edit `~/.local/share/applications/devterm.desktop`.
- The window closes when `tmux.sh` exits (ptyxis default).

## Per-window titles

Every devterm window shares the same dock icon (`utilities-terminal`) — GNOME/ptyxis
can't give each window its own taskbar icon the way the Windows side does. Instead we
tell the windows apart by **title**: `tmux.sh` sets the window title to
`devterm: <session>` on attach (an OSC 0 escape; see `attach_session` in `tmux.sh`),
and "devterm" while you're still on the session picker.

- This is what makes the windows distinguishable in the dock fan-out
  (`click-action = 'focus-or-appspread'`, see `fedora/gnome-tweaks.md`), the Activities
  overview, and alt-tab.
- ptyxis must honor OSC titles for this to work: `ignore-osc-title` must be `false`
  (the default). Check with
  `gsettings get org.gnome.Ptyxis ignore-osc-title`.
- **Do not pass `-T`** (nor use ptyxis's "Set Title" menu): a manually set title is
  pinned and suppresses the OSC title, so every window would just read "devterm".
  That's why the `Exec` above omits `-T`.

## Notes

- Validate the entry with `desktop-file-validate ~/.local/share/applications/devterm.desktop`.
- The installed `~/.local/share/applications/devterm.desktop` is a **copy** of the
  template above — after editing the `Exec` (e.g. to change title/launch behavior),
  re-run the setup `cat` block (or edit the installed file directly) and then
  `update-desktop-database ~/.local/share/applications` for the change to take effect.
- If the entry doesn't show up immediately, re-run `update-desktop-database` or log
  out/in; GNOME usually picks it up within a few seconds.
