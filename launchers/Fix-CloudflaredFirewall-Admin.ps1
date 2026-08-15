$ErrorActionPreference = "Stop"

$basePath = Split-Path -Parent $PSScriptRoot
$cloudflared = Join-Path $basePath "coding-tools-mcp\tools\cloudflared.exe"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script as Administrator."
    }
}

function Ensure-OutboundRule {
    param(
        [string]$DisplayName,
        [string]$Protocol
    )

    $deleteOutput = & netsh advfirewall firewall delete rule name="$DisplayName" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "No previous rule to delete: $DisplayName"
    }

    $addOutput = & netsh advfirewall firewall add rule name="$DisplayName" dir=out action=allow program="$cloudflared" enable=yes protocol=$Protocol remoteport=7844 profile=any 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create firewall rule '$DisplayName': $addOutput"
    }
    Write-Host "Ready: $DisplayName"
}

try {
    Assert-Admin

    if (-not (Test-Path -LiteralPath $cloudflared -PathType Leaf)) {
        throw "cloudflared.exe not found: $cloudflared"
    }

    Ensure-OutboundRule -DisplayName "Coding MCP cloudflared outbound TCP 7844" -Protocol "TCP"
    Ensure-OutboundRule -DisplayName "Coding MCP cloudflared outbound UDP 7844" -Protocol "UDP"

    Write-Host ""
    Write-Host "Firewall rules are ready for:"
    Write-Host $cloudflared
    Write-Host ""
    Write-Host "Next: double-click Stop-CodingMCP.vbs, then Start-CodingMCP.vbs."
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
