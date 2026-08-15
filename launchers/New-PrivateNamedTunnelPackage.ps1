param(
    [string]$Hostname = "",
    [string]$TunnelName = "",
    [string]$RepoPath = "",
    [string]$PackageRoot = "",
    [int]$Port = 8767,
    [switch]$SkipLogin
)

$ErrorActionPreference = "Stop"

$LauncherDir = Split-Path -Parent $PSCommandPath
$BasePath = Split-Path -Parent $LauncherDir
if (-not $RepoPath) {
    $RepoPath = Join-Path $BasePath "coding-tools-mcp"
}
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

$SkillCommon = Join-Path $BasePath "skills\coding-tools-mcp-remote\scripts\common.ps1"
if (-not (Test-Path -LiteralPath $SkillCommon -PathType Leaf)) {
    throw "common.ps1 not found: $SkillCommon"
}
. $SkillCommon

if (-not $PackageRoot) {
    $label = ($Hostname -replace '^https?://', '' -replace '/.*$', '')
    $label = ($label -split '\.')[0]
    $label = ($label.ToLowerInvariant() -replace '[^a-z0-9-]+', '-').Trim('-')
    if (-not $label) {
        $label = "mcp-device"
    }
    $PackageRoot = Join-Path $BasePath "private-runtime-packages\$label"
}

function Invoke-CloudflaredChecked {
    param(
        [string]$Cloudflared,
        [string[]]$Arguments,
        [switch]$Passthrough
    )

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($Passthrough) {
            & $Cloudflared @Arguments
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                throw "cloudflared $($Arguments -join ' ') failed with exit code $exitCode."
            }
            return ""
        }

        $output = (& $Cloudflared @Arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "cloudflared $($Arguments -join ' ') failed with exit code $exitCode.`n$output"
        }
        return $output
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
}

function Get-TunnelIdFromText {
    param([string]$Text)

    foreach ($pattern in @('ID:\s*([0-9a-fA-F-]{36})', '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')) {
        $match = [regex]::Match($Text, $pattern)
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }
    return ""
}

if (-not $Hostname) {
    throw "Hostname is required, for example: -Hostname 'mcp-pc2.example.com'"
}
$Hostname = ($Hostname.Trim().TrimEnd("/") -replace '^https?://', '' -replace '/.*$', '').ToLowerInvariant()
if ($Hostname -notmatch '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$') {
    throw "Invalid hostname: $Hostname"
}
if (-not $TunnelName) {
    $label = ($Hostname -split '\.')[0]
    $TunnelName = "coding-tools-mcp-$label"
}
if ($TunnelName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{1,62}[A-Za-z0-9]$') {
    throw "Invalid tunnel name: $TunnelName"
}
$TunnelName = $TunnelName.ToLowerInvariant()

$cloudflared = Get-CtmCloudflaredExe -RepoPath $RepoPath
$userCloudflaredDir = Join-Path $env:USERPROFILE ".cloudflared"
$certPath = Join-Path $userCloudflaredDir "cert.pem"
if (-not $SkipLogin -and -not (Test-Path -LiteralPath $certPath -PathType Leaf)) {
    Write-Host "Cloudflare login will open a browser."
    Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "login") -Passthrough | Out-Null
}

$infoText = ""
try {
    $infoText = Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "info", $TunnelName)
} catch {
    Write-Host "Creating tunnel: $TunnelName"
    try {
        Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "create", $TunnelName) -Passthrough | Out-Null
    } catch {
        if (-not $SkipLogin) {
            Write-Host "Cloudflare login is required. Finish the browser login, then this script will continue."
            Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "login") -Passthrough | Out-Null
            Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "create", $TunnelName) -Passthrough | Out-Null
        } else {
            throw
        }
    }
    $infoText = Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "info", $TunnelName)
}

$tunnelId = Get-TunnelIdFromText -Text $infoText
if (-not $tunnelId) {
    throw "Could not determine tunnel UUID from cloudflared tunnel info output."
}

$credentialCandidate = Join-Path $userCloudflaredDir "$tunnelId.json"
if (-not (Test-Path -LiteralPath $credentialCandidate -PathType Leaf)) {
    $foundCredential = Get-ChildItem -Path $userCloudflaredDir -Filter "$tunnelId.json" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $foundCredential) {
        throw "Tunnel credential file not found for $tunnelId under $userCloudflaredDir."
    }
    $credentialCandidate = $foundCredential.FullName
}

$runtimeDir = Join-Path $PackageRoot "coding-tools-mcp\.runtime"
$tunnelDir = Join-Path $runtimeDir "cloudflared"
New-Item -ItemType Directory -Force -Path $tunnelDir | Out-Null

$localCredential = Join-Path $tunnelDir "$tunnelId.json"
Copy-Item -LiteralPath $credentialCandidate -Destination $localCredential -Force

$namedConfigPath = Join-Path $tunnelDir "config.yml"
$yaml = @(
    "tunnel: $tunnelId",
    "credentials-file: $localCredential",
    "ingress:",
    "  - hostname: $Hostname",
    "    service: http://127.0.0.1:$Port",
    "  - service: http_status:404"
)
$yaml | Set-Content -Encoding UTF8 -LiteralPath $namedConfigPath

Write-Host "Routing DNS: $Hostname -> $TunnelName"
Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "route", "dns", "--overwrite-dns", $TunnelName, $Hostname) -Passthrough | Out-Null
Invoke-CloudflaredChecked -Cloudflared $cloudflared -Arguments @("tunnel", "--config", $namedConfigPath, "ingress", "validate") -Passthrough | Out-Null

$config = @{
    tunnel_mode = "named"
    named_hostname = $Hostname
    named_tunnel_name = $TunnelName
    named_tunnel_id = $tunnelId
    named_config_path = $namedConfigPath
    port = $Port
    oauth_password = New-CtmUrlSafeToken -ByteCount 32
    oauth_token_secret_hex = New-CtmHexSecret -ByteCount 32
    oauth_token_ttl_seconds = 604800
    keepalive_seconds = 30
    public_failure_restart_count = 2
    public_health_timeout_seconds = 10
    prevent_sleep = $true
    allow_network = $true
    permission_mode = "dangerous"
    workspace_path = ""
}
($config | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runtimeDir "chatgpt-mcp-config.json")

$readme = @(
    "PRIVATE Coding MCP runtime package",
    "",
    "This package contains secrets. Do not upload it to GitHub.",
    "",
    "MCP URL:",
    "https://$Hostname/mcp",
    "",
    "How to use on the other computer:",
    "1. Clone the public GitHub repo.",
    "2. Copy this package's coding-tools-mcp\.runtime into the cloned coding-tools-mcp folder.",
    "3. Start Coding MCP and choose the workspace folder on that computer.",
    "",
    "Tunnel name: $TunnelName",
    "Tunnel id: $tunnelId"
)
$readme | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $PackageRoot "README-PRIVATE.txt")

Write-Host "Private package created:"
Write-Host $PackageRoot
Write-Host "MCP URL:"
Write-Host "https://$Hostname/mcp"
Write-Host "OAuth password:"
Write-Host $config["oauth_password"]
