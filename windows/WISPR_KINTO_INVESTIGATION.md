# Wispr Flow under Kinto — full investigation & handoff

**Status: SOLVED (2026-06-22) — see §12 for the implemented fix.** The sections
below are the investigation that led there; read §12 first. This documents
everything learned so a fresh session can pick up without re-deriving it. Read this top to bottom before proposing or trying
anything — several "obvious" ideas have already been tried and ruled out, and a
couple of long-standing assumptions in older notes turned out to be **wrong** (see
"Corrected misconceptions").

Date of this writeup: 2026-06-22. Related: `MigratingToKinto.md`,
and memories `wispr-flow-terminal-paste`, `kinto-migration`, `registry-ctrl-alt-swap`.

---

## 1. Goal

The user dictates with **Wispr Flow** (push-to-talk). They want the transcribed
text to land in the focused app — **including Windows Terminal** — cleanly, the
same as on a Mac. This must NOT regress the Kinto Mac-muscle-memory setup, and in
particular **must not break terminal `Ctrl+C`** (SIGINT).

The user's hard requirement, stated repeatedly: any solution that makes **the
Windows clipboard-history panel pop up after a recording is unacceptable.**

---

## 2. Current machine state (the baseline everything runs against)

- **Kinto** (github.com/rbreaves/kinto) owns Mac-style remapping. It is an
  **AutoHotkey v1** script at `~/.kinto/kinto.ahk`, currently **100% STOCK**
  (restored from `~/.kinto/kinto.ahk.stock-bak`). Do not assume it's patched.
- Kinto runs **elevated** via a **logon Scheduled Task** named `Kinto`
  (RunLevel Highest, no time limit, runs on battery). Confirmed Running; the AHK
  process shows a blank command line because it's elevated — that's expected.
  (As of this writeup: a single `AutoHotkey*` PID, elevated, = Kinto. No companion
  is running.)
- Keymap = **Windows keyboard** (`toggle_kb.bat win`), NOT Apple.
- AHK exe used: `C:\Program Files\AutoHotkey\v1.1.37.01\AutoHotkeyU64.exe`.
- The **old** architecture (registry Ctrl↔Alt Scancode Map swap +
  `windows/autohotkey.ahk` per-terminal un-swap) is **retired** — registry value
  removed, old AHK not in Startup. Kept only for rollback. Do NOT reintroduce it.

### Kinto's relevant remaps (Windows keymap, "WinModifiers")
```
$LAlt::LCtrl      ; physical Alt  -> Ctrl   (this is "Cmd" — Cmd+C/V/X/A/…)
$RAlt::RCtrl
$LWin::LAlt       ; physical Win  -> Alt
$LCtrl::LWin      ; physical Ctrl -> Win    (leftmost key opens Start)
$RCtrl::RAlt
```
So: **physical Ctrl → Win**, **physical Alt → Ctrl**, **physical Win → Alt**.
- Terminal paste handler lives in Kinto's *terminals* app-group: `$^v::` (sends
  `Ctrl+Shift+V`). SIGINT is offered on `$^.::` (Cmd+.) and `$#c::` (Win+C).
- Windows Terminal `settings.json` (repo + live): copy=`ctrl+shift+c`,
  paste=`ctrl+shift+v` **and** `alt+v`; `copyOnSelect:true`. There is **no**
  `ctrl+v`→paste binding right now (it was added during the invasive fix, then
  reverted).

---

## 3. THE CORE PROBLEM (why Wispr breaks under Kinto)

Wispr inserts text by **injecting a hardcoded `Ctrl+V`** (not configurable; there
is no "type instead of paste" mode). That injected `Ctrl` is **not** marked with
AHK's KEY_IGNORE, so **Kinto's keyboard hook sees it and remaps it**:

> Wispr injects **Ctrl+V** → Kinto's `$LCtrl::LWin` turns the Ctrl into **Win** →
> the app receives **Win+V** → **Windows Clipboard-History panel pops up** (and,
> due to a timing race in the injected batch, sometimes only a stray `v` lands).

This is the mechanism behind BOTH long-observed symptoms: the "stray `v` ~1/10"
AND the "clipboard panel appears." **It fires on every recording**, the moment
Wispr auto-pastes — independent of anything we add. Even with clipboard history
toggled off, Win+V still shows the "want to turn on clipboard history?" popup.
(Note: registry `HKCU\Software\Microsoft\Clipboard\EnableClipboardHistory`
currently reads `1`/enabled despite the user believing it's off — but disabling it
does **not** fix this; the panel/popup is a *symptom* of the stray Win+V.)

**This is why the user rejects the companion-paste idea (Section 5): it pastes
fine, but Wispr's own auto-paste still pops the panel after every recording.**

---

## 4. Corrected misconceptions (older notes/docs are WRONG on these)

1. **"Wispr leaves the dictated text on the clipboard, so just paste manually with
   Cmd+V."** — FALSE in the current Wispr version. Wispr does a **clipboard-
   preserving paste**: it backs up the clipboard, sets it to the transcript, fires
   Ctrl+V, then **restores your original clipboard**. After a (failed) auto-paste
   there is **nothing useful on the clipboard** to paste. The "manual Cmd+V"
   workaround in `MigratingToKinto.md` / the wispr memory therefore does **not**
   actually recover the dictation. Treat those notes as outdated.

2. **"No external fix is possible; a companion can't help."** — TOO BROAD. The
   earlier failed attempt was a companion **HOOK** that tried to *tag Wispr's
   injected keys* with KEY_IGNORE so Kinto would ignore them. That fails because
   **AHK keeps its own LL keyboard hook at the top of the chain**, so an external
   hook (even elevated, installed after Kinto) can't pre-empt Kinto's remap. BUT a
   companion that **generates its own keystrokes** works fine (Section 5) — those
   carry KEY_IGNORE automatically. The distinction matters:
   - companion **HOOK** (re-tag someone else's injected input) → **FAILS**.
   - companion **SEND** (emit your own input) → **WORKS**.

---

## 5. What is PROVEN to work (but insufficient on its own)

**A separate AHK companion doing `Send` bypasses Kinto and pastes cleanly.**
Because AHK stamps everything it `Send`s with `dwExtraInfo == KEY_IGNORE`
(`0xFFC3D44F`), and **every** AHK hook (including Kinto's) ignores input carrying
that marker — regardless of which AHK process produced it. So a companion script's
`Send ^v` reaches the app as a real `Ctrl+V` (Kinto never touches it).

Proven by experiment (user confirmed pasting works in Notepad/GUI **and** Windows
Terminal):
```ahk
#SingleInstance force
F8::
  if WinActive("ahk_exe WindowsTerminal.exe")
    Send ^+v       ; WT's paste is Ctrl+Shift+V
  else
    Send ^v        ; everything else pastes on Ctrl+V
return
```
This is the current content of the throwaway test file
`C:\Users\joepaley\kinto-paste-test.ahk` (the companion process has been killed; the
file is harmless and can be deleted).

**Why it's not enough:** the companion can *paste*, but it needs the transcript on
the clipboard, and (per #4.1) Wispr doesn't leave it there. More importantly, the
companion does nothing about Wispr's **auto-paste**, which still fires after every
recording and pops the Win+V panel (Section 3). **User has rejected this path.**

### 5a. The "Copy last transcript" sub-idea (also insufficient)
Wispr has two transcript actions:
- **"Paste last transcript"** (default `Shift+Alt+Z`) — pastes via Ctrl+V → same
  breakage.
- **"Copy last transcript"** (default `Shift+Alt+X`) — copies the transcript to
  the clipboard with **no paste keystroke** (so no Kinto conflict for the copy
  itself). **This action is NOT exposed in Wispr's Settings UI** (can't rebind it
  there) but it **is active on its default `Alt+Shift+X`**.

Idea was: companion does `Send !+x` (→ Wispr copies transcript to clipboard, clean)
then `Send ^v`/`^+v` (→ paste). One key = copy-last + paste, no Wispr rebinding.
Not pursued to completion because it **still doesn't stop the auto-paste panel**,
and `Send !+x` risks tripping Windows' Alt+Shift layout-switch hotkey. Parked.

---

## 6. The invasive fix that WORKS but was rejected (do not silently re-apply)

Editing Kinto so `Ctrl+V` hits **no** AHK hotkey (in `~/.kinto/kinto.ahk` comment
out `$LCtrl::LWin` and the `$LCtrl up::` Start-menu hack, delete the `$^v::`
handler; add `ctrl+v`→paste to WT) makes Wispr **100% reliable** — verified.

**Cost (why rejected):** making physical Ctrl pass through natively makes it
**indistinguishable from Cmd** (Cmd = physical Alt → Ctrl). Kinto can then no
longer tell a *copy* (Cmd+C) from *SIGINT* (Ctrl+C) in the terminal, so
**terminal `Ctrl+C` stops interrupting** (SIGINT moves to Cmd+.), and physical
Ctrl stops opening Start. User: "Revert the wispr fix in kinto, that was too
invasive." It is reverted. Backup of stock at `~/.kinto/kinto.ahk.stock-bak`.

---

## 7. Avenues NOT yet tried (most promising first)

1. **Disable Wispr's auto-paste, if such a setting/flag exists.** If Wispr can be
   told to dictate **without** auto-pasting (leave it in history / on clipboard
   only), then the Win+V panel never fires, and the proven companion (Section 5)
   can do the paste on a hotkey. *Open question to investigate in Wispr settings /
   config (`%APPDATA%\Wispr Flow\config.json`) / support.* This is the cleanest
   path IF auto-paste is disableable. Note Wispr has a server-controlled
   `shift-insert` feature flag (default off) that uses Shift+Insert instead of
   Ctrl+V — but only for VS Code/Cursor/Windsurf **integrated** terminals, not
   Windows Terminal.

2. **Briefly suspend Kinto during the dictation→paste window** (the user's original
   "disable AHK until we see the paste" idea). Trigger off the **Shift+F1 listen
   key**: on listen-start, suspend Kinto; after the paste completes, resume. With
   Kinto suspended, Wispr's injected Ctrl+V passes natively → pastes, no Win+V,
   fully automatic, no companion paste needed. **Hard parts:** (a) the companion
   must be **elevated** to control elevated Kinto (PostMessage the AHK Suspend
   command, ID 65305 — but that's a *toggle*, desync-prone); (b) **resume timing**
   — the paste happens an unpredictable 1–3 s after you stop talking
   (speech + transcription), so resume on a clipboard-change + short delay, with a
   max-timeout safety net; (c) during suspension Mac shortcuts are off (acceptable
   while dictating). Fragile but would be fully automatic. NOT yet attempted under
   stock Kinto.

3. **A type-not-paste dictation tool instead of Wispr** (e.g. **Windows Voice
   Typing**, Win+H) — types characters, no Ctrl+V, so zero Kinto conflict. Loses
   Wispr's quality/features. Fallback if 1 and 2 fail.

4. **Patch Wispr itself** (Electron `app.asar`, ~164 MB, auto-updates frequently
   to change its paste from Ctrl+V to Shift+Insert or typing). High effort, breaks
   on every Wispr update. Last resort. User did file a Wispr support request
   (via their "report an issue" field) asking for a configurable paste method.

### Ruled out — do NOT re-attempt
- Companion **hook** that re-tags Wispr's injected keys (AHK hook ordering — #4.2).
- The Kinto edit in Section 6 (breaks terminal Ctrl+C).
- The old registry Ctrl↔Alt swap + per-terminal un-swap (whole retired arch).
- Manual "Cmd+V after dictating" as a *recovery* (clipboard is restored — #4.1).

---

## 8. Key technical facts (quick reference)

- **KEY_IGNORE = `0xFFC3D44F`** in `dwExtraInfo`. AHK `Send` sets it; all AHK hooks
  ignore input carrying it, cross-process. This is the entire reason a companion
  `Send` bypasses Kinto.
- **LL hook ordering:** AHK keeps its hook at the top; you can't reliably install
  *above* a running AHK (Kinto). So you can't intercept/modify keys *before* Kinto
  — you can only emit your own (which it then ignores) or control Kinto itself
  (suspend/kill).
- **Wispr paste = injected Ctrl+V**, clipboard-preserving (restores your clipboard
  after), not configurable. Actions: Paste-last = Shift+Alt+Z; Copy-last =
  Shift+Alt+X (not in UI). Listen/push-to-talk trigger = **Shift+F1** (user's
  binding). Config: `%APPDATA%\Wispr Flow\config.json`; data in `flow.sqlite`
  (feature flags are server-fetched, not stored locally).
- **Why native Ctrl+V can't just be allowed:** Cmd (physical Alt) already maps to
  Ctrl; letting physical Ctrl be native too makes Cmd and Ctrl indistinguishable,
  which is what breaks terminal Ctrl+C (Section 6).

---

## 9. Artifacts / where things are

- Stock Kinto: `~/.kinto/kinto.ahk` (+ backup `kinto.ahk.stock-bak`).
- Kinto launcher (path-fixed): `~/.kinto/kinto-start.vbs`.
- Throwaway paste test (safe to delete): `C:\Users\joepaley\kinto-paste-test.ahk`.
- Runbook: `windows/MigratingToKinto.md` (its Wispr section's "manual Cmd+V"
  recommendation is **outdated** per #4.1 — fix when this is resolved).
- WT settings: `windows/windows-terminal/settings.json` (no ctrl+v→paste binding).
- Memories: `wispr-flow-terminal-paste`, `kinto-migration`,
  `registry-ctrl-alt-swap` (this file is the authoritative, corrected source;
  the wispr memory points here).

---

## 10. Recommended next step for a fresh session

Start with **Avenue #1**: determine whether Wispr can be configured to NOT
auto-paste (settings, `config.json`, or ask Wispr support). If yes → stock Kinto +
companion `Send ^v`/`^+v` on a hotkey is a clean, non-invasive solution that never
pops the panel. If no → evaluate **Avenue #2** (suspend Kinto during the
Shift+F1→paste window) vs **#3** (Windows Voice Typing). Do **not** reopen the
ruled-out items in Section 7. Confirm direction with the user before implementing —
they care most about (a) no clipboard panel, (b) terminal Ctrl+C intact.

---

## 11. Hidden-settings dig (2026-06-22) — what the app bundle actually has

Investigated `config.json`, `flow.sqlite`, leveldb, `Preferences`, `session.json`,
the Electron `app.asar`, and `Release\Wispr Flow Helper.exe`. Findings:

- **`shift-insert` is a real feature flag and it is ALREADY ENABLED on this
  account** — `logs\main.log` shows `"shift-insert":{"enabled":true}`. Wispr *can*
  paste via Shift+Insert. So why does Windows Terminal still get Ctrl+V→Win+V?
  Because the flag is **app-scoped in code**, not global — it only switches the
  paste keystroke for specific integrations (the helper has `CursorIntegration`
  paths; Wispr's docs say shift-insert covers VS Code/Cursor/Windsurf *integrated*
  terminals only). Windows Terminal and ordinary apps still get **Ctrl+V**.
  **There is no local payload / app-list to widen it** — the flag value is just
  `{enabled:true}`; the scoping is hardcoded.
- **Feature flags are server-controlled (PostHog)**, delivered via an
  `UpdateFeatureFlags` IPC payload and cached **in memory** (`getFeatureFlagData`,
  `getFeatureFlagCacheAsRecord`). They are **NOT** stored in any user-editable
  local file (not in config.json / sqlite / leveldb / Preferences). So you can't
  flip one by editing a file — it'd need a server/PostHog change (i.e., Wispr
  support) or patching the bundle.
- **`windows-key-up-simulation` flag = `{enabled:false}`** on this account. It's
  plausibly related to clean key injection on Windows (the old "Win key stuck"
  class). Worth asking Wispr to enable it as an experiment — also server-side.
- **The actual keystroke injection + paste-method decision lives in
  `Release\Wispr Flow Helper.exe`** (a .NET helper) driven by IPC command types:
  `ShiftInsert`, `SimulateKeyPress`, `PasteText`. It also has
  `CursorIntegration.DisableClipboardRestore` — confirming Wispr's normal paste
  **restores the clipboard** (matches §4.1), and that the no-restore behavior is
  wired only for the Cursor integration.
- **No "disable auto-paste for dictation" setting exists.** `prefs.user` has
  `polishAutoPaste:true` (that's the *Polish* feature only) and `aiFormatting`,
  etc., but nothing to stop the post-dictation auto-paste. The `prefs.user.internal`
  block has hidden toggles (`isEnsembleModelEnabled`, `experimentalAsrVariant`,
  `shouldSaveAxText`, scratchpad/meeting flags) — **none control the paste method.**
- **No "type instead of paste" mode** anywhere in the bundle.
- Confirmed keybinds (`config.json` → `prefs.user.shortcuts`): **Shift+F1 = `ptt`**
  (push-to-talk), **Shift+F2 = `paste_last_text`**, **Ctrl+V = `paste_event`**,
  **Shift+Alt+X = `copy_last_text`** (not exposed in the Settings UI),
  Esc = dismiss. `modifierShortcut:"164"` (Alt).

**Bottom line of the dig:** there is **no local hidden setting** that disables
auto-paste or forces Shift+Insert globally. The only in-app levers (`shift-insert`
scope, `windows-key-up-simulation`) are **server-side PostHog flags** → would
require Wispr support. So the practical options remain: **(a) ask Wispr support to
widen `shift-insert` to all apps / Windows Terminal** (clean if granted — Shift+Insert
isn't remapped by Kinto, so no Win+V); **(b) suspend Kinto during the paste window**
(§7.2); **(c) Windows Voice Typing** (§7.3); or **(d) patch the bundle** (last
resort, breaks on update). Avenue #1 as originally framed (a local auto-paste
off-switch) does **not** exist.

### 11a. External research (ChatGPT, 2026-06-22) — confirms server-side only
Independent web research confirmed the bundle dig: **no public/documented way** to
force Shift+Insert globally or for Windows Terminal, **no** "transcribe but don't
auto-paste" setting, and **no** "type as keystrokes" mode. Wispr's own docs say
Shift+Insert is used **only** for VS Code / Cursor / Windsurf **integrated**
terminals; everywhere else (incl. Windows Terminal, "Direct paste: Yes") it uses
the system paste = **Ctrl+V**. A Wispr status incident confirms desktop paste
behavior is changed via their **feature-flag service** (server/remote config), not
a local knob. `windows-key-up-simulation` is undocumented publicly; best guess is
it simulates a Win key-up to clear a stuck Win modifier (relevant to our Ctrl→Win
case) — enable-able only by Wispr support if at all.

### 11b. Two concrete actions that came out of this
1. **Interim workaround that works TODAY, zero risk:** dictate into the
   **Windsurf / VS Code integrated terminal** for terminal work — `shift-insert` is
   already enabled on this account and applies there, so Wispr uses Shift+Insert
   (Kinto doesn't touch Shift/Insert) → clean paste, no Win+V panel. Does NOT help
   standalone **Windows Terminal** or GUI apps (still Ctrl+V → Win+V).
2. **The real fix = Wispr support ticket** (only they can flip the server flag).
   Precise ask: *"My account already has the Shift+Insert terminal feature flag,
   but it only applies to VS Code/Cursor/Windsurf integrated terminals. Please
   enable Shift+Insert paste globally on Windows, or at least for Windows Terminal
   / OpenConsole / wt.exe — or add a 'copy only / don't auto-paste' or 'type as
   keystrokes' mode. I use Kinto (AutoHotkey Mac-style remapper) that maps physical
   Ctrl→Win, so Flow's injected Ctrl+V becomes Win+V and opens Clipboard History.
   Also: can you enable `windows-key-up-simulation` for my account?"*

---

## 12. SOLUTION (implemented 2026-06-22) — suspend Kinto around the paste

Avenue #2 from §7, built and confirmed working in Notepad + Windows Terminal. A
small **elevated** AHK companion `~/.kinto/wispr-suspend.ahk` watches Wispr's
push-to-talk key (Shift+F1) and:
- on **Shift+F1 release** (just before Wispr transcribes + pastes), **suspends
  Kinto** via `PostMessage WM_COMMAND 65305` ("Suspend Hotkeys") to Kinto's elevated
  AHK window;
- with Kinto suspended, Wispr's injected **Ctrl+V passes natively** (no Ctrl-to-Win
  remap) => clean paste, **no Win+V clipboard panel**;
- **resumes Kinto** ~700 ms after the next clipboard change (Wispr sets the
  clipboard right before pasting), with a 15 s safety timeout — so the suspend
  window is ~1 s and **can never stick**.

What made it work / gotchas:
- **Companion must be elevated** (UIPI: only an equal/higher-integrity process can
  message elevated Kinto). Autostart = logon Scheduled Task **`WisprKintoSuspend`**
  (RunLevel Highest, no time limit, on battery), installed by
  `~/.kinto/install-wispr-suspend-task.ps1`. Repo copies:
  `windows/kinto/wispr-suspend.ahk` + `windows/kinto/install-wispr-suspend-task.ps1`.
- **Windows Terminal needs a `ctrl+v`->paste binding** (added to
  `windows/windows-terminal/settings.json`): during the suspend window Wispr fires
  native Ctrl+V, but WT's paste is Ctrl+Shift+V. Safe — normal physical Ctrl+V under
  Kinto becomes Win+V (never `ctrl+v`), and it doesn't touch Ctrl+C.
- **No manual suspend toggle** in the companion. AHK's suspend is a *blind toggle*,
  so a stray manual toggle desyncs our belief vs. Kinto's real state (hit this during
  testing => Kinto stuck suspended => physical keys went native, and physical Cmd+C
  in a terminal hit Zoom's global Ctrl+Shift+C). The companion does only the
  strictly-paired auto cycle and **resets its belief if Kinto's window handle
  changes** (Kinto restart).
- **Kinto stays 100% stock** — no `kinto.ahk` edits, so terminal Ctrl+C, Cmd
  shortcuts, and Start-via-physical-Ctrl are all intact. The remap is off only for
  ~1 s per dictation.

Residual notes:
- During that ~1 s window physical modifiers are native, so a key pressed *then*
  could hit a native global hotkey (e.g. Wispr's own Left-Alt `modifierShortcut`, or
  any Alt/Win combo). Harmless in practice — you're waiting for the paste, not typing.
- Unrelated gotcha found en route: **Zoom Clips** registers a global **Ctrl+Shift+C**
  that collides with terminal copy (Kinto sends Ctrl+Shift+C for Cmd+C in terminals),
  popping Zoom's "Record new clip" on Cmd+C in a terminal. Fix = disable that global
  shortcut in Zoom -> Settings -> Keyboard Shortcuts. Not related to this fix.

Verify: `Get-ScheduledTask WisprKintoSuspend` shows Running; log at
`~/.kinto/wispr-suspend.log` shows `SUSPEND ... RESUME` pairs around each dictation.
Pending: a reboot test (dictate into Notepad + Windows Terminal after restart) to
confirm both the Kinto and WisprKintoSuspend tasks come up.
