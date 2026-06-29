# devterm per-session icons

`devterm` gives each terminal window its own taskbar button + icon, keyed on the
tmux session name (see `meta/devterm-tag-watcher.ps1`).

By default the icon is **generated**: a colored circle with the session's
initials, the color hashed deterministically from the session name and cached
under `%LOCALAPPDATA%\devterm\icons\`.

## Overriding a session's icon

Drop a file named `<session>.ico` in **this** folder and it wins over the
generated icon. The name is the session name with non-alphanumeric characters
stripped (e.g. session `feature-123` → `feature123.ico`).

The override is read each time a window attaches, so a new `.ico` takes effect on
the next `devterm` launch for that session — no rebuild needed.
