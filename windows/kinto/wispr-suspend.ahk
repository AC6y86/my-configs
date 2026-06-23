; Wispr-under-Kinto fix: briefly SUSPEND Kinto around Wispr's paste so Wispr's
; injected Ctrl+V passes natively (no Kinto Ctrl->Win remap => no Win+V clipboard
; panel). Suspends on Shift+F1 RELEASE (just before transcription+paste), resumes
; after the paste (clipboard change + short delay), with a safety timeout so the
; suspend window is ~1s and can never stick.
;
; Must run ELEVATED (to message the elevated Kinto via UIPI). Autostarts via the
; "WisprKintoSuspend" logon Scheduled Task (see install-wispr-suspend-task.ps1).
; Deploy: copy to ~/.kinto/wispr-suspend.ahk and run the installer.
; Log: %A_ScriptDir%\wispr-suspend.log . AHK v1.
;
; NOTE: no manual toggle hotkeys on purpose -- a stray toggle desyncs our belief
; from Kinto's real state. The only toggles are the strictly-paired auto cycle,
; and we reset our belief whenever Kinto's window handle changes (Kinto restarted).
#NoEnv
#SingleInstance force
#Persistent
DetectHiddenWindows, On
SetBatchLines, -1
SetWinDelay, -1

global KintoHwnd := 0
global Suspended := false
global Armed := false
global RESUME_DELAY := 700     ; ms after clipboard change to let the paste land
global SAFETY := 15000         ; ms hard cap: always resume even if no paste seen
global LOGF := A_ScriptDir "\wispr-suspend.log"

FindKinto()
Log("=== started; Kinto hwnd=" KintoHwnd " ===")
return

Log(msg) {
    global LOGF
    FormatTime, ts,, yyyy-MM-dd HH:mm:ss
    FileAppend, % ts " " msg "`n", % LOGF
}

; Locate Kinto's AHK main window. If the handle changed since last time, Kinto
; (re)started -- it boots ACTIVE, so reset our suspend belief to match.
FindKinto() {
    global KintoHwnd, Suspended
    prev := KintoHwnd
    found := 0
    WinGet, lst, List, ahk_class AutoHotkey
    Loop, %lst% {
        h := lst%A_Index%
        WinGetTitle, t, ahk_id %h%
        if (InStr(t, "kinto.ahk")) {
            found := h
            break
        }
    }
    KintoHwnd := found
    if (found && found != prev) {
        if (prev)
            Log("Kinto window changed -> assume active (restart)")
        Suspended := false
    }
    return found
}

SuspendKinto() {
    global KintoHwnd, Suspended
    FindKinto()
    if (KintoHwnd && !Suspended) {
        PostMessage, 0x111, 65305, , , ahk_id %KintoHwnd%   ; WM_COMMAND "Suspend Hotkeys" (toggle ON)
        Suspended := true
        Log("SUSPEND")
    } else if (!KintoHwnd) {
        Log("SUSPEND skipped: Kinto window not found")
    }
}

ResumeKinto() {
    global KintoHwnd, Suspended
    if (KintoHwnd && Suspended && WinExist("ahk_id " KintoHwnd)) {
        PostMessage, 0x111, 65305, , , ahk_id %KintoHwnd%   ; toggle back OFF
        Log("RESUME")
    }
    Suspended := false   ; always clear belief on resume
}

; Wispr push-to-talk = Shift+F1. Pass through (~) so Wispr still receives it.
~+F1 up::
    SuspendKinto()
    Armed := true
    SetTimer, SafetyResume, -%SAFETY%
return

OnClipboardChange:
    if (Armed) {
        Armed := false
        SetTimer, SafetyResume, Off
        SetTimer, DoResume, -%RESUME_DELAY%
    }
return

DoResume:
    ResumeKinto()
return

SafetyResume:
    Armed := false
    ResumeKinto()
return
