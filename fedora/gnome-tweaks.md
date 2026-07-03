# Fedora / GNOME desktop tweaks

UX customizations for the native Linux (Fedora) desktop. These are GNOME Shell
settings applied with `gsettings` (stored in dconf, so they persist across
reboots automatically — no file in this repo is "sourced"). This doc is the
record of what was changed and how to re-apply or roll back each tweak.

## Environment

- **Fedora**, GNOME Shell **50.2**, **Wayland** session.
- Dock is the **Dash to Dock** extension (`dash-to-dock@micxgx.gmail.com`), not
  stock GNOME. Its behavior is configured under the
  `org.gnome.shell.extensions.dash-to-dock` gsettings schema.
- Other enabled extensions (for context): `xremap@k0kubun.com`,
  `appindicatorsupport@rgcjonas.gmail.com`, `background-logo@fedorahosted.org`.

List enabled extensions any time with:

```bash
gnome-extensions list --enabled
```

## Dock click → fan out all windows ("appspread")

**Problem:** clicking an app icon in the dock cycled through that app's windows
one at a time (each click brought back a *different* single window). The default
was `click-action = 'cycle-windows'`.

**Fix:** set the click action to `focus-or-appspread`, which fans out (spreads)
all of the app's windows across the screen, macOS App-Exposé style, so you can
pick one.

```bash
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'focus-or-appspread'
```

Applies live — no logout needed.

**Behavior / caveat:** Dash to Dock has no "spread on *every* click" value;
`focus-or-appspread` is the closest:

- App **not** focused → first click raises/focuses it (all its windows come to
  the front).
- App **already** focused → click fans all its windows out; click one to focus it.

So from another app it can take two clicks (focus, then fan); if the app is
already active, one click fans.

**Verify:**

```bash
gsettings get org.gnome.shell.extensions.dash-to-dock click-action
# -> 'focus-or-appspread'
```

**Roll back** to the previous behavior (or the extension default):

```bash
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'cycle-windows'
# or: gsettings reset org.gnome.shell.extensions.dash-to-dock click-action
```

**Other available `click-action` values** (for reference):
`skip, minimize, launch, cycle-windows, minimize-or-overview, previews,
minimize-or-previews, focus-or-previews, focus-or-appspread,
focus-minimize-or-previews, focus-minimize-or-appspread, quit`.
