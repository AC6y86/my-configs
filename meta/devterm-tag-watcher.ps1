# devterm-tag-watcher.ps1
#
# Started (hidden) by devterm.ps1 just before it launches a new Windows Terminal
# window. Waits for that window to attach to a tmux session -- at which point
# tmux.sh sets the caption to "devterm: <session>" -- then gives the window its
# own taskbar identity: a per-session AppUserModelID + icon.
#
# Why this is needed: all wt.exe windows are hosted by a single
# WindowsTerminal.exe process, so they share one taskbar button by default. The
# only lever for a separate, custom-icon taskbar button per window is overriding
# that window's property store (System.AppUserModel.ID + RelaunchIconResource)
# and then forcing the shell to recreate the taskbar button (hide/show), because
# the shell only reads a window's AUMID when it first creates the button.
#
# Icons are generated per session (a colored circle with the session's initials,
# color hashed from the name) and cached. Drop "<session>.ico" in
# windows/devterm-icons/ to override a specific session.

param(
    # How long to wait for the new window to attach to a session before giving up.
    [int]$TimeoutSec = 300,
    [int]$PollMs     = 400
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$OverrideDir = Join-Path $PSScriptRoot "..\windows\devterm-icons"
$CacheDir    = Join-Path $env:LOCALAPPDATA "devterm\icons"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WinApi {

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit)]
    public struct PROPVARIANT {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr p;   // x64: union data begins at offset 8
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }

    public static class Win {
        [DllImport("shell32.dll")]
        public static extern int SHGetPropertyStoreForWindow(
            IntPtr hwnd, ref Guid riid, out IPropertyStore pps);

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr h, int nCmdShow);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")]
        public static extern bool DestroyIcon(IntPtr h);

        static readonly Guid APPMODEL_FMTID =
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

        static void SetStr(IPropertyStore ps, uint pid, string val) {
            PROPERTYKEY k; k.fmtid = APPMODEL_FMTID; k.pid = pid;
            PROPVARIANT pv; pv.vt = 31; pv.p = Marshal.StringToCoTaskMemUni(val);
            try { ps.SetValue(ref k, ref pv); }
            finally { Marshal.FreeCoTaskMem(pv.p); }
        }

        // pids: AppUserModel.ID=5, RelaunchIconResource=3, RelaunchDisplayName=4.
        public static int SetWindowAppId(
            IntPtr hwnd, string appId, string iconResource, string displayName) {
            Guid iid = typeof(IPropertyStore).GUID;
            IPropertyStore ps;
            int hr = SHGetPropertyStoreForWindow(hwnd, ref iid, out ps);
            if (hr != 0 || ps == null) return hr;
            try {
                if (!string.IsNullOrEmpty(appId))        SetStr(ps, 5, appId);
                if (!string.IsNullOrEmpty(iconResource)) SetStr(ps, 3, iconResource);
                if (!string.IsNullOrEmpty(displayName))  SetStr(ps, 4, displayName);
                ps.Commit();
            } finally { Marshal.ReleaseComObject(ps); }
            return 0;
        }
    }
}
'@

# --- enumerate visible "devterm: <session>" windows ---
function Get-DevtermWindows {
    $list = New-Object System.Collections.ArrayList
    $cb = [WinApi.Win+EnumWindowsProc]{
        param($h, $l)
        if ([WinApi.Win]::IsWindowVisible($h)) {
            $len = [WinApi.Win]::GetWindowTextLength($h)
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][WinApi.Win]::GetWindowText($h, $sb, $sb.Capacity)
                $t = $sb.ToString()
                if ($t -match '^devterm:\s*(.+?)\s*$') {
                    [void]$list.Add([pscustomobject]@{ HWND = $h; Session = $Matches[1] })
                }
            }
        }
        return $true
    }
    [void][WinApi.Win]::EnumWindows($cb, [IntPtr]::Zero)
    return $list
}

function Get-Safe([string]$name) { ($name -replace '[^A-Za-z0-9]', '') }

# Deterministic hue from the session name (FNV-1a).
function Get-Hue([string]$name) {
    $hash = [uint32]2166136261
    foreach ($ch in $name.ToCharArray()) {
        $hash = $hash -bxor [uint32][char]$ch
        # 0xFFFFFFFFL (int64) -- a bare 0xFFFFFFFF parses as int32 -1, which makes
        # the mask a no-op and overflows the [uint32] cast.
        $hash = [uint32](($hash * 16777619) -band 0xFFFFFFFFL)
    }
    return [int]($hash % 360)
}

function ConvertFrom-Hsv([double]$h, [double]$s, [double]$v) {
    $c = $v * $s
    $x = $c * (1 - [math]::Abs((($h / 60) % 2) - 1))
    $m = $v - $c
    switch ([int][math]::Floor($h / 60)) {
        0 { $r = $c; $g = $x; $b = 0 }
        1 { $r = $x; $g = $c; $b = 0 }
        2 { $r = 0; $g = $c; $b = $x }
        3 { $r = 0; $g = $x; $b = $c }
        4 { $r = $x; $g = 0; $b = $c }
        default { $r = $c; $g = 0; $b = $x }
    }
    return [System.Drawing.Color]::FromArgb(255,
        [int](($r + $m) * 255), [int](($g + $m) * 255), [int](($b + $m) * 255))
}

# Return a path to an .ico for the session, generating + caching if needed.
function Get-SessionIcon([string]$session) {
    $safe = Get-Safe $session
    if (-not $safe) { $safe = "session" }

    $override = Join-Path $OverrideDir ("$safe.ico")
    if (Test-Path $override) { return $override }

    [void](New-Item -ItemType Directory -Force -Path $CacheDir)
    $icoPath = Join-Path $CacheDir ("$safe.ico")
    if (Test-Path $icoPath) { return $icoPath }

    $size = 64
    $color = ConvertFrom-Hsv (Get-Hue $session) 0.62 0.82
    $initials = $safe.Substring(0, [math]::Min(2, $safe.Length)).ToUpper()

    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)

    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush, 2, 2, $size - 4, $size - 4)

    $fontPx = if ($initials.Length -ge 2) { 26 } else { 34 }
    $font = New-Object System.Drawing.Font(
        "Segoe UI", $fontPx, [System.Drawing.FontStyle]::Bold,
        [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $g.DrawString($initials, $font, [System.Drawing.Brushes]::White, $rect, $sf)
    $g.Dispose()

    $hicon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hicon)
    $fs = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create)
    try { $icon.Save($fs) } finally { $fs.Dispose() }
    $icon.Dispose()
    [void][WinApi.Win]::DestroyIcon($hicon)
    $bmp.Dispose()
    return $icoPath
}

function Set-WindowIdentity($hwnd, [string]$session) {
    $appId = "Devterm." + (Get-Safe $session)
    $ico = Get-SessionIcon $session
    [void][WinApi.Win]::SetWindowAppId($hwnd, $appId, "$ico,0", "devterm: $session")
    # The shell only reads the AUMID when it creates the taskbar button, so force
    # it to be recreated by hiding then re-showing the window.
    [void][WinApi.Win]::ShowWindow($hwnd, 0)   # SW_HIDE
    Start-Sleep -Milliseconds 120
    [void][WinApi.Win]::ShowWindow($hwnd, 5)   # SW_SHOW
    [void][WinApi.Win]::SetForegroundWindow($hwnd)
}

# --- main: tag the first newly-attached devterm window, then exit ---
# Snapshot devterm windows that already exist (earlier launches, already tagged)
# so we don't re-blink them.
$existing = @{}
foreach ($w in Get-DevtermWindows) { $existing[[int64]$w.HWND] = $true }

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    foreach ($w in Get-DevtermWindows) {
        if (-not $existing.ContainsKey([int64]$w.HWND)) {
            Set-WindowIdentity $w.HWND $w.Session
            exit 0
        }
    }
    Start-Sleep -Milliseconds $PollMs
}
exit 0
