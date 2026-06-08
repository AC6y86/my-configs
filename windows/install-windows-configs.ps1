#!/usr/bin/env pwsh
# Deploys the tracked Windows configs from this repo to their live locations:
#   - PowerShell 7 profile  -> $PROFILE (Documents\PowerShell\...)
#   - Windows Terminal settings.json -> the WT package LocalState folder
#
# The repo is the source of truth. Each destination is backed up to a
# .bak-<timestamp> before being overwritten. Note: Windows Terminal rewrites its
# settings.json when you change settings via the UI, so after intentional UI
# changes, copy the live file back into the repo
# (windows/windows-terminal/settings.json) to keep the tracked copy current.
#
# Usage:  pwsh -File windows\install-windows-configs.ps1

$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

function Deploy($src, $dst) {
    if (-not (Test-Path $src)) { Write-Warning "Source missing, skipping: $src"; return }
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    if (Test-Path $dst) {
        $bak = "$dst.bak-$ts"
        Copy-Item $dst $bak -Force
        Write-Host "Backed up: $dst -> $bak"
    }
    Copy-Item $src $dst -Force
    Write-Host "Deployed:  $src -> $dst"
}

# PowerShell 7 profile. $PROFILE resolves to the current user's pwsh profile path.
$psSrc = Join-Path $PSScriptRoot 'powershell\Microsoft.PowerShell_profile.ps1'
Deploy $psSrc $PROFILE

# Windows Terminal settings.json (stable Store package).
$wtSrc = Join-Path $PSScriptRoot 'windows-terminal\settings.json'
$wtPkg = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Microsoft.WindowsTerminal_*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch 'Preview' } | Select-Object -First 1
if ($wtPkg) {
    Deploy $wtSrc (Join-Path $wtPkg.FullName 'LocalState\settings.json')
} else {
    Write-Warning "Windows Terminal package not found; skipped settings.json deploy."
}

Write-Host "Done. Open a new terminal tab for changes to take effect."
