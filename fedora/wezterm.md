# WezTerm on Fedora — config record

Notes on the WezTerm setup for the native Linux (Fedora) desktop. The live config
is **`~/.config/wezterm/wezterm.lua`** (not symlinked/tracked here — this doc is
the record of what changed and why, with apply/verify/rollback for each item).

## Environment

- **Fedora**, GNOME Shell **50.x**, **Wayland** session with **fractional
  scaling** (1.5 / 1.25).
- Laptop: Lenovo, **Intel Meteor Lake-P** graphics, `i915` kernel driver.
- Default GNOME terminal is **Ptyxis** (Fedora's current default; no GNOME
  Terminal / GNOME Console installed). WezTerm is set up to match it.

WezTerm re-reads its config on save; changes only affect **newly launched**
processes, so fully quit and relaunch after editing. On a bad edit, launch from a
shell with `wezterm start` — Lua errors print to stderr / an error window.

## Hardware acceleration (front end)

**History:** the config once forced CPU rendering with `config.front_end =
'Software'` because a diagnostic said the GPU/Mesa stack was broken (`iris` driver
"failed to load", "failed to create dri3 screen").

**That diagnosis was a false negative.** Those `glxinfo`/`iris` errors came from
running the check inside a **sandboxed shell that never exposes `/dev/dri`**
(stripped `/dev`, everything owned by `nobody:nobody`). On the real desktop the
GPU is healthy — `i915` loads fine (GuC/HuC firmware OK, `/sys/class/drm/card1` +
`renderD128` present with all display outputs), and GNOME itself composites on the
GPU. Both `WebGpu` and `OpenGL` front ends were verified working.

**Fix:** removed the `front_end = 'Software'` line so WezTerm uses its default
(**WebGpu**, hardware-accelerated).

**How to verify hardware accel non-destructively** (run in a real terminal, opens
a new window without editing the config):

```bash
wezterm --config 'front_end="OpenGL"' start   # OpenGL front end
wezterm --config 'front_end="WebGpu"' start    # default; the one that used to panic
```

Check the real GPU state (NOT from a sandboxed shell — it will lie):

```bash
ls /dev/dri/                 # should list card* and renderD128 on the real host
glxinfo -B | grep -i accel   # "Accelerated: yes" when the GPU driver is live
```

**Roll back** (if WebGpu ever panics on launch again): add back
`config.front_end = 'Software'` (CPU/llvmpipe), or try `'OpenGL'` first.

## Wayland disabled (XWayland) — separate, still needed

`config.enable_wayland = false` is intentional and unrelated to the GPU. WezTerm's
Wayland backend rounds fractional scaling to integer `buffer_scale = 2`, produces
a buffer size that isn't a multiple of 2, and GNOME kills the connection:
`wl_surface error 2: Buffer size must be an integer multiple of buffer_scale`.
It also gave no draggable title bar. Forcing X11/XWayland fixes both. **Leave it.**

## Font + colors match GNOME terminal (Ptyxis)

**Goal:** WezTerm looked different from Ptyxis — grey text vs white, and a
different font. Ptyxis renders the **system monospace font** (`use-system-font =
true` → `org.gnome.desktop.interface monospace-font-name = 'Adwaita Mono 11'`) and
uses the built-in **`gnome` palette** in **dark** mode (`interface-style = dark`,
desktop `color-scheme = prefer-dark`), whose foreground is white `#ffffff`.
WezTerm set no font/colors, so it used bundled JetBrains Mono + a grey-fg default.

**Where the exact palette came from** — Ptyxis embeds palettes as gresources:

```bash
gresource list /usr/bin/ptyxis | grep -i palette
gresource extract /usr/bin/ptyxis /org/gnome/Ptyxis/palettes/gnome.palette
```

Use the `[Dark]` section (session is `prefer-dark`). Find the live settings with:

```bash
gsettings get org.gnome.desktop.interface monospace-font-name   # 'Adwaita Mono 11'
gsettings get org.gnome.desktop.interface color-scheme          # 'prefer-dark'
uuid=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")
gsettings get "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$uuid/" palette
# -> 'gnome'
```

**Fix:** in `~/.config/wezterm/wezterm.lua`:

```lua
config.font = wezterm.font 'Adwaita Mono'
config.font_size = 11.0

-- GNOME "gnome" palette, [Dark] variant.
config.colors = {
  foreground = '#ffffff',
  background = '#1c1c1f',
  cursor_bg = '#ffffff',
  cursor_border = '#ffffff',
  cursor_fg = '#1c1c1f',
  ansi = {    '#241f31','#c01c28','#2ec27e','#f5c211',
              '#1e78e4','#9841bb','#0ab9dc','#c0bfbc' },
  brights = { '#5e5c64','#ed333b','#57e389','#f8e45c',
              '#51a1ff','#c061cb','#4fd2fd','#f6f5f4' },
}
```

**Notes / caveats:**

- Selection color is omitted on purpose — Ptyxis derives it from the GNOME system
  accent (`UseSystemAccent=true`), which has no fixed hex. Add `selection_bg` /
  `selection_fg` if you want to pin it.
- Palette is hardcoded to **dark**; if you switch GNOME to light, swap in the
  `[Light]` values from the extracted palette.
- `Adwaita Mono` ships in `adwaita-mono-fonts` (`/usr/share/fonts/`).

**Verify:**

```bash
# Font actually loaded:
WEZTERM_LOG=config,font=info wezterm start   # look for "Adwaita Mono"
# ANSI colors, side-by-side vs Ptyxis:
for i in {0..15}; do printf "\e[48;5;${i}m  \e[0m"; done; echo
```

Foreground text should now be white on the same near-black background. If glyphs
look slightly off-size vs Ptyxis (WezTerm runs under XWayland with fractional
scaling), nudge `font_size` by ±0.5.

**Roll back:** delete the `config.font`, `config.font_size`, and `config.colors`
blocks to return to WezTerm's bundled font + default scheme.
