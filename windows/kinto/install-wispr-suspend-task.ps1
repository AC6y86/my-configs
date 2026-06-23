# Registers the "WisprKintoSuspend" logon Scheduled Task (elevated, so it can
# message the elevated Kinto), then starts it. Re-runnable. RUN ELEVATED, e.g.:
#   Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\joepaley\.kinto\install-wispr-suspend-task.ps1'
# Adjust $user / paths for other machines.
$ErrorActionPreference = "Stop"
$user = "joepaley"
$exe  = "C:\Program Files\AutoHotkey\v1.1.37.01\AutoHotkeyU64.exe"
$arg  = '"C:\Users\joepaley\.kinto\wispr-suspend.ahk"'

$action    = New-ScheduledTaskAction -Execute $exe -Argument $arg
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -RunLevel Highest -LogonType Interactive
# Without -Settings the task inherits Windows' 3-day kill + stop-on-battery; disable both.
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName "WisprKintoSuspend" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

# Start it now. The new AHK instance replaces any manually-launched one (#SingleInstance force).
Start-ScheduledTask -TaskName "WisprKintoSuspend"
Start-Sleep -Seconds 2
Get-ScheduledTask -TaskName "WisprKintoSuspend" | Select-Object TaskName, State | Format-List
Write-Host "Done. WisprKintoSuspend registered + started." -ForegroundColor Green
