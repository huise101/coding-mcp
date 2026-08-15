[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Profile,
    [string]$Root = ".codex-remote"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "remote_profile.ps1")

Assert-RemoteProfileName -Profile $Profile

$storeRoot = Get-RemoteStoreRoot -Root $Root
$profilesDir = Join-Path $storeRoot "profiles"
$secretsDir = Join-Path $storeRoot "secrets"
New-Item -ItemType Directory -Force -Path $profilesDir, $secretsDir | Out-Null

$hostName = Read-Host "SSH host"
if (-not $hostName.Trim()) {
    throw "SSH host is required."
}

$portText = Read-Host "SSH port [22]"
if (-not $portText.Trim()) {
    $portText = "22"
}
if ($portText -notmatch '^\d+$') {
    throw "SSH port must be a number."
}

$userName = Read-Host "SSH user"
if (-not $userName.Trim()) {
    throw "SSH user is required."
}

$workdir = Read-Host "Default remote workdir (optional)"
$keyPath = Read-Host "SSH private key path (optional; leave blank for password login)"

function ConvertTo-EnvValue {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) {
        return ""
    }
    return ($Value -replace "(`r|`n)", "").Trim()
}

$profilePath = Join-Path $profilesDir "$Profile.env"
$credentialPath = Join-Path $secretsDir "$Profile.credential.xml"
$lines = @(
    "# Local profile for windows-remote-server. Do not commit this file if it contains sensitive host details.",
    "REMOTE_HOST=$(ConvertTo-EnvValue $hostName)",
    "REMOTE_PORT=$(ConvertTo-EnvValue $portText)",
    "REMOTE_USER=$(ConvertTo-EnvValue $userName)"
)

if ($workdir.Trim()) {
    $lines += "REMOTE_WORKDIR=$(ConvertTo-EnvValue $workdir)"
}

if ($keyPath.Trim()) {
    $lines += "REMOTE_KEY=$(ConvertTo-EnvValue $keyPath)"
    if (Test-Path -LiteralPath $credentialPath) {
        Remove-Item -LiteralPath $credentialPath -Force
    }
}
else {
    $credential = Get-Credential -UserName $userName -Message "Enter SSH password for $userName@$hostName. It will be encrypted for this Windows user."
    $credential | Export-Clixml -LiteralPath $credentialPath
    $lines += "REMOTE_CREDENTIAL_XML=secrets/$Profile.credential.xml"
}

Set-Content -LiteralPath $profilePath -Value $lines -Encoding UTF8

Write-Host "Profile saved: $profilePath"
if (-not $keyPath.Trim()) {
    Write-Host "Encrypted credential saved: $credentialPath"
}
Write-Host "Use this in chat: profile: $Profile"
