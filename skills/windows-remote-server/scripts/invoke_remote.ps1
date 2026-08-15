[CmdletBinding(DefaultParameterSetName = "Command")]
param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [Parameter(Mandatory = $true, ParameterSetName = "Command")][string]$Command,
    [Parameter(Mandatory = $true, ParameterSetName = "CommandFile")][string]$CommandFile,
    [string]$Root = ".codex-remote",
    [string]$Python = "python",
    [switch]$Pty
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "remote_profile.ps1")

try {
    Use-RemoteProfile -Profile $Profile -Root $Root

    $remoteExec = Join-Path $scriptDir "remote_exec.py"
    $args = @("-B", $remoteExec)

    if ($PSCmdlet.ParameterSetName -eq "Command") {
        $args += @("--cmd", $Command)
    }
    else {
        $args += @("--cmd-file", $CommandFile)
    }

    if ($Pty) {
        $args += "--pty"
    }

    & $Python @args
    exit $LASTEXITCODE
}
finally {
    Remove-Item Env:REMOTE_PASSWORD -ErrorAction SilentlyContinue
}
