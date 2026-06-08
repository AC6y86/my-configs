#!/usr/bin/env pwsh
# Copies autohotkey.ahk into the Windows Startup folder (replacing the old copy)
# and restarts the running AutoHotkey instance so changes take effect immediately.
#
# Usage:  pwsh -File windows\install-autohotkey.ps1

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'autohotkey.ahk'
if (-not (Test-Path $source)) {
    Write-Error "Source script not found: $source"
    exit 1
}

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$dest = Join-Path $startupDir 'autohotkey.ahk'

# 1. Copy over the old version.
Copy-Item -Path $source -Destination $dest -Force
Write-Host "Copied: $source -> $dest"

# 2. Stop the running AutoHotkey instance(s) for this script.
#    Filter by command line so we don't kill unrelated AHK scripts; fall back to
#    all AutoHotkey processes if the command-line filter matches nothing.
$ahkProcs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
$targets = $ahkProcs | Where-Object { $_.CommandLine -and $_.CommandLine -match 'autohotkey\.ahk' }
if (-not $targets) { $targets = $ahkProcs }

foreach ($p in $targets) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        Write-Host "Stopped AutoHotkey (PID $($p.ProcessId))"
    } catch {
        Write-Warning "Could not stop PID $($p.ProcessId): $_"
    }
}

# 3. Relaunch the copied script (Windows shell association picks the AHK runtime).
try {
    Start-Process -FilePath $dest
    Write-Host "Restarted AutoHotkey from Startup."
} catch {
    Write-Warning "Copied the file, but could not relaunch AutoHotkey: $_"
    Write-Warning "Is AutoHotkey installed and associated with .ahk files?"
    exit 1
}
