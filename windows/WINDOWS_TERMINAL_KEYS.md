# Windows terminal key handling — how the layers fit together

Reference for the Ctrl/Alt + terminal key setup. Read this before touching
`windows/autohotkey.ahk` swap blocks, the PowerShell profile, or Windows
Terminal keybindings — the layers interact and the root cause is non-obvious.

## The foundational fact: Ctrl/Alt are swapped at the REGISTRY level

There is a **Scancode Map** under
`HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout` that swaps the two
modifiers **system-wide**:
- physical **Ctrl (0x1D) → Alt (0x38)**
- physical **Alt (0x38) → Ctrl (0x1D)**

So in any app with no further remapping, the physical Ctrl key acts as Alt and
vice-versa. This is intentional (global preference). Everything else below
exists to cope with it.

## The layers (in order a keypress travels)

1. **Registry Scancode Map** — swaps Ctrl<->Alt for the whole OS.
2. **AutoHotkey** (`windows/autohotkey.ahk`) — sees the already-swapped keys and
   selectively **un-swaps** them inside terminals so terminals get normal
   modifiers:
   - Per-terminal `#IfWinActive` blocks with `LCtrl::LAlt` + `LAlt::LCtrl`
     (mintty, `ConsoleWindowClass`, VNC, and **`WindowsTerminal.exe`**). Two
     swaps cancel out → terminal sees real Ctrl/Alt.
   - Emacs-style hotkeys (`!a !e ^f ^g !y !k`) are wrapped in **`#If !is_target()`**
     so they are completely inert in terminals (otherwise they intercept the
     swapped Alt and re-send it, collapsing Ctrl-A and Alt-A together).
   - **Do NOT use `LCtrl & Tab::` (or any `LCtrl &` custom combo).** Making LCtrl
     a prefix key breaks the `LCtrl::LAlt` half of every un-swap block, so only
     one direction fires (symptom: physical Alt stays Ctrl, e.g. Alt-C
     interrupts while Ctrl-C should). It was disabled for this reason.
3. **Windows Terminal `settings.json`** (per-user, not in repo, but mirrored to
   `windows/windows-terminal/settings.json`):
   - `copy` is on **ctrl+shift+c**, `paste` on **ctrl+shift+v**, so `ctrl+c`
     passes through to the shell (interrupt/SIGINT) instead of being captured by
     copy. `copyOnSelect: true` keeps select=auto-copy.
   - `paste` is also bound to **alt+v** (Mac-like Cmd-V — the thumb/Cmd-position
     key is physical Alt). Captured here at the WT layer so it does not fall
     through to the shell as readline `Meta-v`.
4. **The shell**:
   - **WSL/bash** uses readline in emacs mode by default — the reference.
   - **PowerShell 7** profile (`windows/powershell/Microsoft.PowerShell_profile.ps1`,
     live `$PROFILE`) sets `Set-PSReadLineOption -EditMode Emacs` to match bash,
     plus `Set-PSReadLineKeyHandler -Chord 'Ctrl+c' -Function CopyOrCancelLine`
     because emacs mode otherwise leaves Ctrl+C unbound (it just beeps).

## Net result in a terminal (WSL or PowerShell)

- **Ctrl+A** = beginning of line, **Ctrl+E** = end, **Ctrl+C** = interrupt /
  cancel line, etc. — physical Ctrl behaves as Ctrl.
- **Alt** behaves as Meta (Alt+B/F/D word ops, etc.) — physical Alt behaves as Alt.
- WSL and PowerShell behave the same.
- In non-terminal Windows apps the registry swap stays in effect and the AHK
  emacs bindings are active (the intended global behavior).

## Symptom -> cause cheat sheet

- **Ctrl-C "capitalizes the first letter" in bash** = Ctrl arrived as Alt
  (Meta-c = capitalize-word) → a terminal un-swap block is missing/disabled.
- **Ctrl-C just beeps in PowerShell** = same swap reaching PSReadLine as Alt+C
  (unbound) OR (separately) emacs mode left Ctrl+C unbound.
- **Ctrl-A and Alt-A do the same thing** = emacs `!a` hotkey intercepting the
  swapped key in a terminal → needs the `#If !is_target()` guard.
- **One direction works, the other "swapped"** (e.g. Alt-C interrupts, Ctrl-C
  doesn't) = an `LCtrl &` prefix key is breaking `LCtrl::LAlt`.

## Deploying

- AHK: `pwsh -File windows\install-autohotkey.ps1` (copies to Startup, restarts AHK).
- PowerShell profile + WT settings: `pwsh -File windows\install-windows-configs.ps1`
  (backs up each live file first). Open a new tab for changes to take effect.
