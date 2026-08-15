[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [Parameter(Mandatory = $true)][ValidateSet("upload", "download")][string]$Action,
    [Parameter(Mandatory = $true)][string]$Local,
    [Parameter(Mandatory = $true)][string]$Remote,
    [string]$Root = ".codex-remote",
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "remote_profile.ps1")

try {
    Use-RemoteProfile -Profile $Profile -Root $Root

    $transfer = Join-Path $scriptDir "transfer.py"
    & $Python -B $transfer $Action --local $Local --remote $Remote
    exit $LASTEXITCODE
}
finally {
    Remove-Item Env:REMOTE_PASSWORD -ErrorAction SilentlyContinue
}
