# set-window-appid.ps1 -- PROOF OF CONCEPT
#
# Forces a per-window AppUserModelID (AUMID) + taskbar icon onto an existing
# top-level window, found by a substring of its title. This is the risky bit of
# giving each devterm its own taskbar entry: Windows Terminal hosts all windows
# in one process, so the only lever for separate taskbar buttons + custom icons
# is overriding each HWND's property store after the window exists.
#
# Test:
#   1. Launch devterm, pick a tmux session (title becomes "devterm: <name>").
#   2. Run:  pwsh -File set-window-appid.ps1 -TitleMatch "devterm: main" `
#              -AppId "Devterm.main" -IconPath "C:\Windows\System32\shell32.dll" -IconIndex 13
#   3. Look at the taskbar: did that window split into its own button with the
#      shell32 icon (a little computer/printer icon)? If yes, the approach works.
#
# If nothing changes (or it reverts when you switch tabs/title), WT is stomping
# the property store and we fall back to a per-process terminal.

param(
    [string]$TitleMatch = "devterm:",
    [string]$AppId      = "Devterm.Test",
    # RelaunchIconResource takes "<file>,<index>". A DLL/EXE with an icon index,
    # or a path to a .ico with index 0.
    [string]$IconPath   = "C:\Windows\System32\shell32.dll",
    [int]$IconIndex     = 13,
    [string]$DisplayName = "",
    # The shell only reads a window's AUMID when it first creates the taskbar
    # button. Setting it on an already-shown window won't regroup unless we force
    # the button to be recreated by hiding + re-showing the window.
    [switch]$ForceRegroup,
    # Just dump every visible top-level window title and exit (diagnostic).
    [switch]$List
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace WinApi {

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public uint pid;
    }

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

        // System.AppUserModel.* keys share this fmtid; pids: ID=5,
        // RelaunchIconResource=3, RelaunchDisplayNameResource=4.
        static readonly Guid APPMODEL_FMTID =
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

        static void SetStr(IPropertyStore ps, uint pid, string val) {
            PROPERTYKEY k;
            k.fmtid = APPMODEL_FMTID;
            k.pid = pid;
            PROPVARIANT pv;
            pv.vt = 31;                                  // VT_LPWSTR
            pv.p = Marshal.StringToCoTaskMemUni(val);
            try { ps.SetValue(ref k, ref pv); }
            finally { Marshal.FreeCoTaskMem(pv.p); }
        }

        // Returns the HRESULT from SHGetPropertyStoreForWindow (0 = success).
        // Doing the whole sequence in C# avoids PowerShell's broken late-binding
        // on the IUnknown-only IPropertyStore.
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
            } finally {
                Marshal.ReleaseComObject(ps);
            }
            return 0;
        }
    }
}
'@

# --- diagnostic: list every visible top-level window title ---
if ($List) {
    $all = New-Object System.Collections.ArrayList
    $cbAll = [WinApi.Win+EnumWindowsProc]{
        param($h, $l)
        if ([WinApi.Win]::IsWindowVisible($h)) {
            $len = [WinApi.Win]::GetWindowTextLength($h)
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][WinApi.Win]::GetWindowText($h, $sb, $sb.Capacity)
                [void]$all.Add([pscustomobject]@{ HWND = $h; Title = $sb.ToString() })
            }
        }
        return $true
    }
    [void][WinApi.Win]::EnumWindows($cbAll, [IntPtr]::Zero)
    $all | Format-Table -Auto -Wrap
    exit 0
}

# --- find the window by title substring ---
$found = New-Object System.Collections.ArrayList
$cb = [WinApi.Win+EnumWindowsProc]{
    param($h, $l)
    if ([WinApi.Win]::IsWindowVisible($h)) {
        $len = [WinApi.Win]::GetWindowTextLength($h)
        if ($len -gt 0) {
            $sb = New-Object System.Text.StringBuilder ($len + 1)
            [void][WinApi.Win]::GetWindowText($h, $sb, $sb.Capacity)
            $t = $sb.ToString()
            if ($t -like "*$TitleMatch*") { [void]$found.Add(@{ h = $h; t = $t }) }
        }
    }
    return $true
}
[void][WinApi.Win]::EnumWindows($cb, [IntPtr]::Zero)

if ($found.Count -eq 0) {
    Write-Error "No visible window with title containing '$TitleMatch'. Is devterm open on that session?"
    exit 1
}
if ($found.Count -gt 1) {
    Write-Host "Multiple matches; using the first:" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "  [$($_.h)] $($_.t)" }
}
$hwnd  = $found[0].h
$title = $found[0].t
Write-Host "Target window: [$hwnd] '$title'" -ForegroundColor Cyan

# --- set AUMID + icon via the C# helper ---
$iconRes = "{0},{1}" -f $IconPath, $IconIndex
$hr = [WinApi.Win]::SetWindowAppId($hwnd, $AppId, $iconRes, $DisplayName)
if ($hr -ne 0) {
    Write-Error ("SHGetPropertyStoreForWindow failed: 0x{0:X8}" -f $hr); exit 1
}

Write-Host "Set AUMID='$AppId', icon='$iconRes'." -ForegroundColor Green

if ($ForceRegroup) {
    # SW_HIDE = 0, SW_SHOW = 5. Hiding then showing makes the shell destroy and
    # recreate the taskbar button, so it re-reads the new AUMID for grouping.
    Write-Host "Forcing taskbar button recreation (hide/show)..." -ForegroundColor Cyan
    [void][WinApi.Win]::ShowWindow($hwnd, 0)
    Start-Sleep -Milliseconds 120
    [void][WinApi.Win]::ShowWindow($hwnd, 5)
    [void][WinApi.Win]::SetForegroundWindow($hwnd)
}

Write-Host "Check the taskbar." -ForegroundColor Green
