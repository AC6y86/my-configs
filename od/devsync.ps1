#Requires -Version 7.0
<#
.SYNOPSIS
    Sync files between local machine and On-Demand devserver.

.DESCRIPTION
    Uses dev.exe to find running OD instances, then syncs via rsync (if available)
    or scp. Rsync only transfers changed files; scp transfers everything.

.PARAMETER From
    Remote path on devserver (default: /home/joepaley/persistent)

.PARAMETER To
    Local path (default: persistent/ in current directory)

.PARAMETER Push
    Sync local → remote (default is remote → local)

.PARAMETER DryRun
    Preview only, no actual transfer

.PARAMETER Delete
    Remove extraneous files at destination (mirror mode, rsync only)

.PARAMETER Exclude
    Exclude pattern (can specify multiple, rsync only)

.PARAMETER TargetHost
    Specify host by index (1,2,...) or name (e.g., 28677.od)

.EXAMPLE
    devsync
    # Pull ~/persistent → ./persistent/

.EXAMPLE
    devsync -Push
    # Push ./persistent/ → ~/persistent

.EXAMPLE
    devsync -DryRun
    # Preview what would transfer

.EXAMPLE
    devsync -Push -Delete
    # Push and remove extra files on remote

.EXAMPLE
    devsync -Exclude "*.o","*.tmp"
    # Exclude patterns (rsync only)
#>

[CmdletBinding()]
param(
    [string]$From = "/home/joepaley/persistent",
    [string]$To = "persistent",
    [switch]$Push,
    [switch]$DryRun,
    [switch]$Delete,
    [string[]]$Exclude = @(),
    [Alias("H")]
    [string]$TargetHost
)

$ErrorActionPreference = "Stop"

$User = "joepaley"
$SshExe = "C:\Windows\System32\OpenSSH\ssh.exe"
$ScpExe = "C:\Windows\System32\OpenSSH\scp.exe"

# Check for rsync - prefer MSYS2, fall back to others
$RsyncExe = $null
$RsyncSsh = $null
$rsyncConfigs = @(
    @{ rsync = "C:\msys64\usr\bin\rsync.exe"; ssh = "C:\msys64\usr\bin\ssh.exe" },
    @{ rsync = "rsync.exe"; ssh = $null },
    @{ rsync = "C:\ProgramData\chocolatey\bin\rsync.exe"; ssh = $null }
)
foreach ($config in $rsyncConfigs) {
    if (Test-Path $config.rsync -ErrorAction SilentlyContinue) {
        $RsyncExe = $config.rsync
        if ($config.ssh -and (Test-Path $config.ssh)) {
            $RsyncSsh = $config.ssh
        } else {
            $RsyncSsh = $SshExe
        }
        break
    }
}

$UseRsync = $null -ne $RsyncExe

# Convert Windows path to cygwin path for rsync
function ConvertTo-CygwinPath {
    param([string]$WinPath)
    if ($WinPath -match '^([A-Za-z]):(.*)$') {
        $drive = $matches[1].ToLower()
        $rest = $matches[2] -replace '\\', '/'
        return "/cygdrive/$drive$rest"
    }
    return $WinPath -replace '\\', '/'
}

# Check that dev.exe is available
if (-not (Get-Command "dev.exe" -ErrorAction SilentlyContinue)) {
    Write-Error "dev.exe not found in PATH. Make sure the Meta Dev CLI is installed."
    exit 1
}

# Get list of running OD instances
$output = & dev.exe list 2>&1 | Out-String

# Extract OD hostnames (patterns like "68883.od")
$hostnames = @([regex]::Matches($output, '\b(\d{5,}\.od)\b') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique)

if ($hostnames.Count -eq 0) {
    Write-Host "No OD instances found."
    $answer = Read-Host "Create one? (y/n)"
    if ($answer -match '^[Yy]') {
        & dev.exe connect
        exit 0
    } else {
        exit 0
    }
}

$selectedHost = $null

if ($hostnames.Count -eq 1) {
    $selectedHost = $hostnames[0]
} elseif ($TargetHost) {
    if ($TargetHost -match '^\d+$') {
        $index = [int]$TargetHost
        if ($index -lt 1 -or $index -gt $hostnames.Count) {
            Write-Error "Invalid host index: $TargetHost (must be 1-$($hostnames.Count))"
            exit 1
        }
        $selectedHost = $hostnames[$index - 1]
    } else {
        foreach ($h in $hostnames) {
            if ($h -eq $TargetHost -or $h -eq "$TargetHost.od") {
                $selectedHost = $h
                break
            }
        }
        if (-not $selectedHost) {
            Write-Error "Host not found: $TargetHost"
            Write-Host "Available hosts:"
            foreach ($h in $hostnames) {
                Write-Host "  - $h"
            }
            exit 1
        }
    }
} else {
    Write-Host "Multiple OD instances found:"
    for ($i = 0; $i -lt $hostnames.Count; $i++) {
        Write-Host "  $($i + 1). $($hostnames[$i]).fbinfra.net"
    }
    $choice = Read-Host "Pick one [1-$($hostnames.Count)]"
    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $hostnames.Count) {
        Write-Error "Invalid selection."
        exit 1
    }
    $selectedHost = $hostnames[[int]$choice - 1]
}

# Resolve local path
if ([System.IO.Path]::IsPathRooted($To)) {
    $localPath = $To
} else {
    $localPath = Join-Path (Get-Location) $To
}

# Ensure local directory exists for pull operations
if (-not $Push -and -not (Test-Path $localPath)) {
    New-Item -ItemType Directory -Path $localPath -Force | Out-Null
}

$remoteHost = "${selectedHost}.fbinfra.net"
$remoteSpec = "${User}@${remoteHost}:${From}"

if ($UseRsync) {
    # Build rsync command
    $rsyncArgs = @("-avz", "--progress", "-e", "`"$RsyncSsh`"")

    if ($DryRun) { $rsyncArgs += "--dry-run" }
    if ($Delete) { $rsyncArgs += "--delete" }
    foreach ($pattern in $Exclude) {
        $rsyncArgs += "--exclude=$pattern"
    }

    if ($Push) {
        # Ensure trailing slash on source to sync contents
        $source = "$(ConvertTo-CygwinPath $localPath)/"
        $dest = $remoteSpec
        Write-Host "Pushing (rsync) $localPath -> ${remoteHost}:$From"
    } else {
        # Ensure trailing slash on source to sync contents
        $source = "${remoteSpec}/"
        $dest = ConvertTo-CygwinPath $localPath
        Write-Host "Pulling (rsync) ${remoteHost}:$From -> $localPath"
    }

    $rsyncArgs += $source
    $rsyncArgs += $dest

    if ($DryRun) {
        Write-Host "[DRY RUN]"
    }

    # Execute rsync
    $cmd = "$RsyncExe $($rsyncArgs -join ' ')"
    Write-Host "Running: $cmd" -ForegroundColor DarkGray
    Invoke-Expression $cmd
} else {
    # Fall back to scp
    Write-Host "Note: rsync not found, using scp (transfers all files)" -ForegroundColor Yellow
    Write-Host "Install MSYS2 for efficient delta sync: https://www.msys2.org/" -ForegroundColor Yellow
    Write-Host ""

    if ($DryRun) {
        if ($Push) {
            Write-Host "[DRY RUN] Would push:"
            Write-Host "  From: $localPath"
            Write-Host "  To:   $remoteSpec"
            Write-Host ""
            Write-Host "Local contents:"
            Get-ChildItem -Path $localPath -Recurse -Name
        } else {
            Write-Host "[DRY RUN] Would pull:"
            Write-Host "  From: $remoteSpec"
            Write-Host "  To:   $localPath"
            Write-Host ""
            Write-Host "Remote contents:"
            & $SshExe "${User}@${remoteHost}" "ls -laR $From"
        }
    } else {
        if ($Push) {
            Write-Host "Pushing (scp) $localPath -> ${remoteHost}:$From"
            $items = Get-ChildItem -Path $localPath
            foreach ($item in $items) {
                & $ScpExe -r $item.FullName "${remoteSpec}/"
            }
        } else {
            Write-Host "Pulling (scp) ${remoteHost}:$From -> $localPath"
            & $ScpExe -r "${remoteSpec}/*" $localPath
        }
    }
}
