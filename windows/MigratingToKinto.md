# Migrating a Windows machine to Kinto (Mac-style keyboard)

A battle-tested runbook for switching a Windows workstation from the old
**registry Ctrl↔Alt swap + `autohotkey.ahk` un-swap** setup (the state every
machine in this repo starts in) to **[Kinto](https://github.com/rbreaves/kinto)**
for reliable Mac muscle memory.

**Why Kinto instead of the old swap:** Kinto's app-aware ruleset is far more
maintainable than the registry-swap + per-terminal-un-swap setup, and it nails
Mac muscle memory (Cmd on the Alt key, terminal copy/paste vs SIGINT, word/line
nav) out of the box.

> **Using Wispr Flow (dictation)?** Its hardcoded `Ctrl+V` auto-paste conflicts
> with Kinto. A patch *can* make it 100% reliable, but it has a real cost —
> **terminal `Ctrl+C` stops interrupting** (SIGINT moves to `Cmd+.`). We judged
> that too invasive and stayed on **stock Kinto + manual paste** (see the Wispr
> Flow section).

**Resulting key layout (Windows keymap):**
- **Cmd = physical Alt** (key left of space) → Cmd+C/V/X/A/Z/S/F/T/W, Cmd+Tab
- **Option/Meta = physical Win**
- **Start menu = physical Ctrl** (leftmost)

---

## Pre-flight

- **IT/security:** Kinto installs a global keyboard hook and an elevated auto-start.
  On a Meta-managed machine confirm this is allowed. (AHK itself is already on the
  image.)
- **Know your AutoHotkey path.** Kinto needs AHK **v1**. Find the exe:
  ```powershell
  Get-ChildItem "C:\Program Files\AutoHotkey" -Recurse -Filter "AutoHotkeyU64.exe" | Select FullName
  ```
  Typically `C:\Program Files\AutoHotkey\v1.1.37.01\AutoHotkeyU64.exe`. Note it —
  you'll need it twice (Kinto's installer can't auto-install AHK here; see Gotchas).
- **Back up the current registry swap value** (for rollback). It should read:
  `00 00 00 00 00 00 00 00 03 00 00 00 1D 00 38 00 38 00 1D 00 00 00 00 00`
  ```powershell
  (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" "Scancode Map")."Scancode Map" | % { $_.ToString("X2") }
  ```

## Step 1 — Tear down the OLD remapper (do this BEFORE Kinto)

The old layer must be gone or it fights Kinto.

1. Remove the custom AHK from autostart and kill it:
   ```powershell
   Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\autohotkey.ahk" -Force
   Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
     ? { $_.CommandLine -match 'autohotkey\.ahk' } | % { Stop-Process -Id $_.ProcessId -Force }
   ```
2. Remove the registry Ctrl↔Alt swap (**elevated** PowerShell):
   ```powershell
   Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map"
   ```
3. **Log off / reboot** — the Scancode Map only changes at login. After re-login
   the keyboard is plain Windows (no Mac remap yet) — expected.

## Step 2 — Install Kinto

```powershell
iwr https://raw.githubusercontent.com/rbreaves/kinto/master/install/windows.ps1 -UseBasicParsing | iex
```
**At the keymap prompt, choose `2` (Windows keyboard standard)** for a standard
PC/laptop keyboard. Do NOT choose `1` (Apple) unless you're literally using an
Apple-branded keyboard — picking Apple on a PC keyboard puts Cmd on the wrong key
and makes the Windows key dead (see Gotchas).

## Step 3 — Fix Kinto's launcher path

Kinto's `choco install autohotkey.install` **fails** on Meta machines (choco is
pinned to an internal mirror that lacks the package), so its launcher points at a
non-existent `C:\Program Files\AutoHotkey\AutoHotkey.exe`. Repoint it at the real
v1 exe from pre-flight:
```powershell
(Get-Content "$env:USERPROFILE\.kinto\kinto-start.vbs") `
  -replace 'C:\\Program Files\\AutoHotkey\\AutoHotkey\.exe',
           'C:\Program Files\AutoHotkey\v1.1.37.01\AutoHotkeyU64.exe' |
  Set-Content "$env:USERPROFILE\.kinto\kinto-start.vbs"
```
(Adjust the version to match your installed AHK.)

## Step 4 — Reliable auto-start (recommended: Scheduled Task)

Kinto's Startup `.vbs` uses `runas` (elevation), but **Windows does not auto-elevate
Startup items at logon**, so Kinto silently won't start on boot. Replace it with a
**logon Scheduled Task running with highest privileges** (starts elevated, no UAC
prompt). Elevated PowerShell:
```powershell
# (elevated PowerShell) stop any running Kinto first
Get-Process AutoHotkey* -ErrorAction SilentlyContinue | Stop-Process -Force

$exe = "C:\Program Files\AutoHotkey\v1.1.37.01\AutoHotkeyU64.exe"
$arg = '"' + $env:USERPROFILE + '\.kinto\kinto.ahk" win'
$action    = New-ScheduledTaskAction -Execute $exe -Argument $arg
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
# IMPORTANT: without -Settings the task inherits Windows' defaults — a 3-day
# ExecutionTimeLimit and stop-on-battery — which would kill Kinto. Disable both
# so it runs indefinitely, on battery too.
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName "Kinto" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

# remove Kinto's own Startup launcher so it doesn't double-run / prompt UAC
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\kinto-start.vbs" -Force -ErrorAction SilentlyContinue

# start it now (or just reboot)
Start-ScheduledTask -TaskName "Kinto"
```
Verify: `Get-ScheduledTask Kinto` shows State **Running** with RunLevel **Highest**,
and exactly one `AutoHotkey*` process is live (its command line shows blank because
it's elevated — expected). `LastTaskResult 267009` = "currently running" (not an error).
*Simpler alternative:* keep Kinto's `.vbs` in Startup and just accept the UAC
prompt at each login.

## Wispr Flow — the fix (suspend Kinto around the paste)

**Problem:** Wispr auto-pastes by injecting a **hardcoded `Ctrl+V`** (not
configurable; no "type" mode). Stock Kinto's `$LCtrl::LWin` remaps that injected
Ctrl to **Win**, so the app gets **Win+V** -> the Windows clipboard-history panel
pops on every dictation (and a race sometimes drops a stray `v`). Editing Kinto so
Ctrl+V passes natively *does* fix Wispr but makes physical Ctrl indistinguishable
from Cmd -> **breaks terminal `Ctrl+C`** -- rejected. (Full investigation, including
why a companion *hook* and the various Wispr settings/flags don't work, is in
`windows/WISPR_KINTO_INVESTIGATION.md`.)

**The fix (Kinto stays 100% stock):** a tiny **elevated** AHK companion that briefly
**suspends Kinto** only around Wispr's paste. On Wispr's push-to-talk key release it
suspends Kinto (so the injected Ctrl+V passes natively -> clean paste, no Win+V),
then resumes ~700 ms after the next clipboard change, with a safety timeout. The
remap is off for only ~1 s per dictation; terminal Ctrl+C, Cmd shortcuts, and
Start-via-Ctrl are untouched.

Deploy (adjust the push-to-talk key in the script if yours isn't Shift+F1, and
`$user`/paths for the machine):
```powershell
# 1) copy the companion + installer into ~/.kinto
Copy-Item "$HOME\my-configs\windows\kinto\wispr-suspend.ahk"             "$env:USERPROFILE\.kinto\" -Force
Copy-Item "$HOME\my-configs\windows\kinto\install-wispr-suspend-task.ps1" "$env:USERPROFILE\.kinto\" -Force
# 2) register + start the elevated logon task (self-elevates; accept UAC)
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$env:USERPROFILE\.kinto\install-wispr-suspend-task.ps1"
```
Then **add a `ctrl+v`->paste keybinding to Windows Terminal**
(`windows/windows-terminal/settings.json`): during the suspend window Wispr fires
native Ctrl+V, but WT's paste is Ctrl+Shift+V. Safe -- normal physical Ctrl+V under
Kinto is Win+V (never `ctrl+v`), and Ctrl+C is untouched. (GUI apps already paste on
native Ctrl+V; no change needed.)

Verify: `Get-ScheduledTask WisprKintoSuspend` = Running; dictate into Notepad and a
Windows Terminal tab -- text pastes, **no clipboard panel**, Ctrl+C still interrupts.
Log: `~/.kinto/wispr-suspend.log` (SUSPEND...RESUME pairs per dictation).

Gotchas:
- Companion **must be elevated** (to message elevated Kinto -- UIPI). The logon task
  handles that.
- **No manual suspend toggle** -- AHK suspend is a blind toggle; a stray toggle
  desyncs belief vs. reality and leaves Kinto stuck suspended (then physical keys go
  native). The script only does the strictly-paired auto cycle + resets on Kinto
  restart.
- **Zoom Clips** (if installed) registers a global **Ctrl+Shift+C** that collides
  with terminal copy (Kinto sends Ctrl+Shift+C for Cmd+C in terminals) -- disable
  that global shortcut in Zoom -> Settings -> Keyboard Shortcuts. Unrelated to Wispr.

## Verification

- **Browser/editor:** physical **Alt+C/V/X/A/Z/S/F/T/W** = copy/paste/cut/select-all/
  undo/save/find/new-tab/close; **Alt+Tab** switches apps; **physical Ctrl** opens Start.
- **Terminal (WSL/PowerShell):** Ctrl+C interrupts; copy/paste work; readline intact.
- **Wispr:** dictation triggers, but auto-paste is unreliable under stock Kinto —
  use manual Cmd+V (see the Wispr Flow section).
- Confirm Kinto is running: `Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" | ? CommandLine -match kinto`.

## Gotchas (all hit during the first migration)

- **Picked the wrong keymap (Apple vs Windows).** Symptoms: Cmd shortcuts land on
  the leftmost key and the Windows key seems dead. Fix without reinstalling:
  ```
  cmd /c "%USERPROFILE%\.kinto\toggle_kb.bat" win
  ```
  then relaunch with the real AHK exe (toggle_kb.bat's own launch path is also the
  bad default and will fail):
  ```powershell
  Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" | ? { $_.CommandLine -match 'kinto' } | % { Stop-Process $_.ProcessId -Force }
  Start-Process "C:\Program Files\AutoHotkey\v1.1.37.01\AutoHotkeyU64.exe" -ArgumentList '"$env:USERPROFILE\.kinto\kinto.ahk" win'
  ```
  (`win`/`mac`/`chrome`/`ibm` are the toggle targets.)
- **`AutoHotkey.exe not found` / Kinto won't run** → the launcher path (Step 3).
- **Kinto doesn't start after reboot** → the elevated-autostart issue (Step 4).
- **choco errors during install** (`127.0.0.1:18081`, python3 already installed) →
  harmless here; AHK is already installed, Kinto just reuses it.
- Kinto editing its own files: switching keymaps / reinstalling **overwrites
  `kinto.ahk` and `kinto-start.vbs`**, so re-apply the Step 3 path fix afterward.

## Rollback (back to the registry swap + old AHK)

1. Stop Kinto / remove its autostart (Startup `.vbs` or the Scheduled Task).
2. Restore the swap (elevated), then log off/reboot:
   ```powershell
   $b = [byte[]](0,0,0,0,0,0,0,0,3,0,0,0,0x1D,0,0x38,0,0x38,0,0x1D,0,0,0,0,0)
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout" -Name "Scancode Map" -Value $b -Type Binary
   ```
3. Re-deploy `windows/autohotkey.ahk` via `windows/install-autohotkey.ps1`.
