Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@

$found = Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -like "*devterm*" } |
    Select-Object -First 1

if ($found -and $found.MainWindowHandle -ne [IntPtr]::Zero) {
    $h = $found.MainWindowHandle
    if ([Win32]::IsIconic($h)) { [Win32]::ShowWindow($h, 9) }
    [Win32]::SetForegroundWindow($h)
} else {
    & wt.exe --title devterm -p Ubuntu -d "\\wsl$\Ubuntu\home\joepaley" -- bash -l -c "~/my-configs/meta/devssh.sh -t"
}
