[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$basePath = Split-Path -Parent $PSScriptRoot
$skillScript = Join-Path $basePath "skills\windows-remote-server\scripts\save_remote_profile.ps1"
$remoteRoot = Join-Path $basePath ".codex-remote"

try {
    if (-not (Test-Path -LiteralPath $skillScript)) {
        throw "Missing windows-remote-server profile script: $skillScript"
    }

    Write-Host "Add remote server profile for Coding MCP"
    Write-Host "Profile store: $remoteRoot"
    Write-Host ""
    $profile = Read-Host "Profile name, for example server1"
    $profile = $profile.Trim()
    if (-not $profile) {
        throw "Profile name is required."
    }
    if ($profile -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid profile name. Use letters, digits, dot, underscore, or hyphen only."
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $skillScript -Profile $profile -Root $remoteRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Profile setup failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "Ready. In ChatGPT/Codex, use profile: $profile"
    Write-Host "Example remote command: remote_exec profile=$profile command='pwd && ls -la'"
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)"
}

Write-Host ""
[void](Read-Host "Press Enter to close")
