param(
    [string]$WorkspacePath,
    [int]$Port = 8767,
    [switch]$ChooseWorkspace,
    [switch]$ResetPassword,
    [switch]$KeepExisting
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$portableRoot = Split-Path -Parent $RepoRoot
$starter = Join-Path $portableRoot "skills\coding-tools-mcp-remote\scripts\Start-CodingToolsMcpRemote.ps1"

if (-not (Test-Path -LiteralPath $starter)) {
    throw "Portable skill starter not found: $starter"
}

$argsList = @("-RepoPath", $RepoRoot, "-Port", $Port)
if ($WorkspacePath) {
    $argsList += @("-WorkspacePath", $WorkspacePath)
}
if ($ChooseWorkspace) {
    $argsList += "-ChooseWorkspace"
}
if ($ResetPassword) {
    $argsList += "-ResetPassword"
}
if ($KeepExisting) {
    $argsList += "-KeepExisting"
}

& $starter @argsList
