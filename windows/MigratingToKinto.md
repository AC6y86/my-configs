# Migrating a Windows machine to Kinto (Mac-style keyboard)

A battle-tested runbook for switching a Windows workstation from the old
**registry Ctrl↔Alt swap + `autohotkey.ahk` un-swap** setup (the state every
machine in this repo starts in) to **[Kinto](https://github.com/rbreaves/kinto)**
for reliable Mac muscle memory.

**Why Kinto instead of the old swap:** Kinto's app-aware ruleset is far more
maintainable than the registry-swap + per-terminal-un-swap setup, and it nails
Mac muscle memory (Cmd on the Alt key, terminal copy/paste vs SIGINT, word/line
nav) out of the box.

> **KNOWN LIMITATION — Wispr Flow auto-paste does NOT work under Kinto** (details
> in the Wispr section below). If reliable dictation-into-any-app matters to you
> more than Mac-style shortcuts, weigh that before migrating — the *old*
> registry-swap setup actually handled Wispr better (it only failed in the
> terminal; Kinto breaks it everywhere).

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

## Wispr Flow — KNOWN LIMITATION (not a step)

Wispr auto-pastes by injecting a **hardcoded `Ctrl+V`** (confirmed in its
`config.json`; the keystroke is not configurable). Kinto remaps `Ctrl` globally
**and** intercepts `Ctrl+V` in its `$^v::` paste handler, so it mangles Wispr's
injected paste — the dictation lands as a stray `v` (or pops `Win+V` clipboard
history), succeeding ~1/10 at best. This is **fundamental**: any global AHK
modifier remapper races Wispr's fast injected keystroke. We tried disabling the
relevant Kinto rules (`$LCtrl::LWin`, the `$^v::` handler) — it only reached ~10%
and changed other behavior, so it was **reverted to stock**.

Workarounds (pick one):
- **Manual paste:** dictate, then paste yourself with **Cmd+V** (physical Alt+V —
  a real keypress Kinto handles correctly). Wispr leaves the text on the clipboard.
- **A dictation tool that *types* instead of pasting** (e.g. Windows Voice
  Typing) — injects characters directly, so no `Ctrl+V` and no conflict.

## Verification

- **Browser/editor:** physical **Alt+C/V/X/A/Z/S/F/T/W** = copy/paste/cut/select-all/
  undo/save/find/new-tab/close; **Alt+Tab** switches apps; **physical Ctrl** opens Start.
- **Terminal (WSL/PowerShell):** Ctrl+C interrupts; copy/paste work; readline intact.
- **Wispr (known broken):** dictation triggers, but auto-paste does NOT land
  reliably — plan to paste manually (Cmd+V). See the Wispr limitation section.
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
