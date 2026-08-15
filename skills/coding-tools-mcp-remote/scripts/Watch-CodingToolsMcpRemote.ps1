param(
    [string]$RepoPath,
    [int]$IntervalSeconds = 10
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$RepoPath = Resolve-CtmRepoPath -RepoPath $RepoPath
$Config = Read-CtmConfig -RepoPath $RepoPath
if (-not $Config.ContainsKey("workspace_path")) {
    $Config["workspace_path"] = Resolve-CtmWorkspace -Config $Config
}
if (-not $Config.ContainsKey("port")) {
    $Config["port"] = 8767
}
if (-not $Config.ContainsKey("tunnel_mode")) {
    $Config["tunnel_mode"] = "quick"
}
if (-not $Config.ContainsKey("oauth_password")) {
    $Config["oauth_password"] = New-CtmUrlSafeToken -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_secret_hex")) {
    $Config["oauth_token_secret_hex"] = New-CtmHexSecret -ByteCount 32
}
if (-not $Config.ContainsKey("oauth_token_ttl_seconds")) {
    $Config["oauth_token_ttl_seconds"] = 604800
}
if (-not $Config.ContainsKey("keepalive_seconds")) {
    $Config["keepalive_seconds"] = 30
}
if (-not $Config.ContainsKey("public_failure_restart_count")) {
    $Config["public_failure_restart_count"] = 2
}
if (-not $Config.ContainsKey("public_health_timeout_seconds")) {
    $Config["public_health_timeout_seconds"] = 10
}
if (-not $Config.ContainsKey("prevent_sleep")) {
    $Config["prevent_sleep"] = $true
}
if (-not $Config.ContainsKey("allow_network")) {
    $Config["allow_network"] = $true
}
if (-not $Config.ContainsKey("permission_mode")) {
    $Config["permission_mode"] = "dangerous"
}
Repair-CtmNamedTunnelConfig -RepoPath $RepoPath -Config $Config | Out-Null
$Config["watcher_pid"] = $PID
Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null

$runtimeDir = Get-CtmRuntimeDir -RepoPath $RepoPath
$serverStdoutLog = Join-Path $runtimeDir "mcp-server-last.stdout.log"
$serverStderrLog = Join-Path $runtimeDir "mcp-server-last.stderr.log"
$cloudflaredStdoutLog = Join-Path $runtimeDir "cloudflared-last.stdout.log"
$cloudflaredStderrLog = Join-Path $runtimeDir "cloudflared-last.stderr.log"

$serverProcess = $null
$cloudflaredProcess = $null
$tunnelUrl = ""
$mcpUrl = ""
$serverPid = 0
$publicFailures = 0
$lastPublicCheck = [DateTime]::MinValue
$keepAwakeFlags = [uint32]2147483649
$keepAwakeEnabled = $false

function Test-ProcessAlive {
    param($Process)
    return ($null -ne $Process -and -not $Process.HasExited)
}

function Enable-CtmKeepAwake {
    if ($script:keepAwakeEnabled) {
        return
    }
    if ($Config.ContainsKey("prevent_sleep") -and -not [bool]$Config["prevent_sleep"]) {
        return
    }
    try {
        Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;

public static class CtmPowerKeepAwake {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
        [CtmPowerKeepAwake]::SetThreadExecutionState($script:keepAwakeFlags) | Out-Null
        $script:keepAwakeEnabled = $true
        Write-CtmLog -RepoPath $RepoPath -Message "system sleep prevention enabled while watcher is running"
    } catch {
        Write-CtmLog -RepoPath $RepoPath -Message "system sleep prevention unavailable: $($_.Exception.Message)"
    }
}

function Update-CtmKeepAwake {
    if ($script:keepAwakeEnabled) {
        try {
            [CtmPowerKeepAwake]::SetThreadExecutionState($script:keepAwakeFlags) | Out-Null
        } catch {
            $script:keepAwakeEnabled = $false
            Write-CtmLog -RepoPath $RepoPath -Message "system sleep prevention stopped: $($_.Exception.Message)"
        }
    }
}

function Stop-TrackedProcess {
    param($Process)
    if (Test-ProcessAlive -Process $Process) {
        try {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        } catch {
        }
    }
}

function Get-QuickTunnelUrlFromLogs {
    $text = ""
    foreach ($path in @($cloudflaredStdoutLog, $cloudflaredStderrLog)) {
        if (Test-Path -LiteralPath $path) {
            $text += "`n" + (Get-Content -Raw -Encoding UTF8 -LiteralPath $path -ErrorAction SilentlyContinue)
        }
    }
    if (-not $text) {
        return ""
    }
    $matches = [regex]::Matches($text, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($matches.Count -eq 0) {
        return ""
    }
    return $matches[$matches.Count - 1].Value
}

function Start-McpServer {
    Set-Content -Encoding UTF8 -LiteralPath $serverStdoutLog -Value ""
    Set-Content -Encoding UTF8 -LiteralPath $serverStderrLog -Value ""

    $python = Get-CtmPythonExe -RepoPath $RepoPath -Config $Config
    $oauthStateFile = Join-Path $runtimeDir "oauth-state.json"
    $envVars = @{
        "CODING_TOOLS_MCP_OAUTH_PASSWORD" = [string]$Config["oauth_password"]
        "CODING_TOOLS_MCP_OAUTH_TOKEN_SECRET" = [string]$Config["oauth_token_secret_hex"]
        "CODING_TOOLS_MCP_OAUTH_TOKEN_TTL" = [string]$Config["oauth_token_ttl_seconds"]
        "CODING_TOOLS_MCP_OAUTH_STATE_FILE" = $oauthStateFile
    }
    if ($Config.ContainsKey("allow_network") -and [bool]$Config["allow_network"]) {
        $envVars["CODING_TOOLS_MCP_ALLOW_NETWORK"] = "1"
    }
    if ($Config.ContainsKey("permission_mode") -and [string]$Config["permission_mode"]) {
        $envVars["CODING_TOOLS_MCP_PERMISSION_MODE"] = [string]$Config["permission_mode"]
    }
    if (([string]$Config["tunnel_mode"]).ToLowerInvariant() -eq "named" -and $Config.ContainsKey("named_hostname")) {
        $envVars["CODING_TOOLS_MCP_SERVER_URL"] = "https://$($Config["named_hostname"])"
    } elseif (([string]$Config["tunnel_mode"]).ToLowerInvariant() -eq "devtunnel" -and $Config.ContainsKey("devtunnel_url")) {
        $envVars["CODING_TOOLS_MCP_SERVER_URL"] = [string]$Config["devtunnel_url"]
    }
    $serverArgs = @(
        "-m",
        "coding_tools_mcp",
        "--workspace",
        [string]$Config["workspace_path"],
        "--host",
        "127.0.0.1",
        "--port",
        [string]$Config["port"],
        "--oauth-mode",
        "--permission-mode",
        [string]$Config["permission_mode"]
    )

    Write-CtmLog -RepoPath $RepoPath -Message "starting MCP server on port $($Config["port"]) for workspace $($Config["workspace_path"])"
    $script:serverProcess = Start-CtmNativeProcess -FilePath $python -Arguments $serverArgs -WorkingDirectory $RepoPath -StdoutPath $serverStdoutLog -StderrPath $serverStderrLog -Environment $envVars
}

function Start-Tunnel {
    Set-Content -Encoding UTF8 -LiteralPath $cloudflaredStdoutLog -Value ""
    Set-Content -Encoding UTF8 -LiteralPath $cloudflaredStderrLog -Value ""

    $mode = ([string]$Config["tunnel_mode"]).ToLowerInvariant()
    if ($mode -eq "named") {
        $cloudflared = Get-CtmCloudflaredExe -RepoPath $RepoPath
        if (-not $Config.ContainsKey("named_tunnel_name") -or -not $Config.ContainsKey("named_config_path") -or -not $Config.ContainsKey("named_hostname")) {
            throw "Named tunnel mode requires named_tunnel_name, named_config_path, and named_hostname in config."
        }
        $script:tunnelUrl = "https://$($Config["named_hostname"])"
        $script:mcpUrl = "$script:tunnelUrl/mcp"
        $tunnelArgs = @("tunnel", "--protocol", "http2", "--edge-ip-version", "4", "--config", [string]$Config["named_config_path"], "run", [string]$Config["named_tunnel_name"])
    } elseif ($mode -eq "devtunnel") {
        if (-not $Config.ContainsKey("devtunnel_id") -or -not [string]$Config["devtunnel_id"]) {
            throw "Dev Tunnel mode requires devtunnel_id in config. Run New-CodingToolsMcpDevTunnel.ps1 first."
        }
        $devtunnel = Get-CtmDevTunnelExe -RepoPath $RepoPath
        $script:tunnelUrl = ""
        $script:mcpUrl = ""
        $tunnelArgs = @("host", [string]$Config["devtunnel_id"])
        Write-CtmLog -RepoPath $RepoPath -Message "starting $mode tunnel"
        $script:cloudflaredProcess = Start-CtmNativeProcess -FilePath $devtunnel -Arguments $tunnelArgs -WorkingDirectory $RepoPath -StdoutPath $cloudflaredStdoutLog -StderrPath $cloudflaredStderrLog
        return
    } else {
        $cloudflared = Get-CtmCloudflaredExe -RepoPath $RepoPath
        $script:tunnelUrl = ""
        $script:mcpUrl = ""
        $tunnelArgs = @("tunnel", "--url", "http://127.0.0.1:$($Config["port"])")
    }

    Write-CtmLog -RepoPath $RepoPath -Message "starting $mode Cloudflare tunnel"
    $script:cloudflaredProcess = Start-CtmNativeProcess -FilePath $cloudflared -Arguments $tunnelArgs -WorkingDirectory $RepoPath -StdoutPath $cloudflaredStdoutLog -StderrPath $cloudflaredStderrLog
}

function Update-Session {
    param([string]$Status, [string]$Message = "")

    $cloudPid = 0
    if (Test-ProcessAlive -Process $cloudflaredProcess) {
        $cloudPid = $cloudflaredProcess.Id
    }
    $watcherPid = $PID
    Write-CtmSession -RepoPath $RepoPath -Config $Config -Status $Status -TunnelUrl $tunnelUrl -McpUrl $mcpUrl -WatcherPid $watcherPid -ServerPid $serverPid -CloudflaredPid $cloudPid -Message $Message | Out-Null
}

Write-CtmLog -RepoPath $RepoPath -Message "watcher started pid=$PID"
Enable-CtmKeepAwake
Update-Session -Status "starting" -Message "watcher started"

while ($true) {
    try {
        $localOk = Test-CtmLocalServer -Port ([int]$Config["port"])
        if (-not $localOk) {
            $owner = Get-CtmPortOwner -Port ([int]$Config["port"])
            if ($owner) {
                Write-CtmLog -RepoPath $RepoPath -Message "port $($Config["port"]) is unhealthy; stopping owner pid=$owner"
                Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
            }
            Stop-TrackedProcess -Process $serverProcess
            Start-McpServer
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Seconds 1
                if (Test-CtmLocalServer -Port ([int]$Config["port"])) {
                    break
                }
            }
        }
        $serverPid = 0
        $ownerPid = Get-CtmPortOwner -Port ([int]$Config["port"])
        if ($ownerPid) {
            $serverPid = $ownerPid
        }

        if (-not (Test-ProcessAlive -Process $cloudflaredProcess)) {
            Start-Tunnel
        }

        $mode = ([string]$Config["tunnel_mode"]).ToLowerInvariant()
        if ($mode -ne "named") {
            if ($mode -eq "devtunnel") {
                $logText = ""
                foreach ($path in @($cloudflaredStdoutLog, $cloudflaredStderrLog)) {
                    if (Test-Path -LiteralPath $path) {
                        $logText += "`n" + (Get-Content -Raw -Encoding UTF8 -LiteralPath $path -ErrorAction SilentlyContinue)
                    }
                }
                $matches = [regex]::Matches($logText, 'https://[a-z0-9.-]+\.devtunnels\.ms')
                $foundUrl = ""
                foreach ($match in $matches) {
                    $candidate = $match.Value.TrimEnd("/")
                    if ($candidate -notmatch '-inspect\.') {
                        $foundUrl = $candidate
                        break
                    }
                }
                if (-not $foundUrl -and $matches.Count -gt 0) {
                    $foundUrl = $matches[0].Value.TrimEnd("/")
                }
            } else {
                $foundUrl = Get-QuickTunnelUrlFromLogs
            }
            if ($foundUrl) {
                $tunnelUrl = $foundUrl
                $mcpUrl = "$tunnelUrl/mcp"
                if ($mode -eq "devtunnel" -and (-not $Config.ContainsKey("devtunnel_url") -or [string]$Config["devtunnel_url"] -ne $tunnelUrl)) {
                    $Config["devtunnel_url"] = $tunnelUrl
                    Save-CtmConfig -RepoPath $RepoPath -Config $Config | Out-Null
                }
            }
        }

        $now = Get-Date
        $keepaliveSeconds = [int]$Config["keepalive_seconds"]
        if ($tunnelUrl -and (($now - $lastPublicCheck).TotalSeconds -ge $keepaliveSeconds)) {
            $lastPublicCheck = $now
            try {
                $healthUrl = "$tunnelUrl/.well-known/oauth-authorization-server"
                $timeoutSeconds = [int]$Config["public_health_timeout_seconds"]
                $response = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec $timeoutSeconds
                if ($response.StatusCode -eq 200) {
                    $publicFailures = 0
                } else {
                    if ($mode -eq "named") {
                        $publicFailures = 0
                        Write-CtmLog -RepoPath $RepoPath -Message "named public health check returned HTTP $($response.StatusCode); keeping tunnel process running"
                    } else {
                        $publicFailures += 1
                        Write-CtmLog -RepoPath $RepoPath -Message "public health check failed $publicFailures time(s): HTTP $($response.StatusCode)"
                    }
                }
            } catch {
                $statusCode = ""
                if ($_.Exception.Response) {
                    try {
                        $statusCode = " HTTP $([int]$_.Exception.Response.StatusCode)"
                    } catch {
                    }
                }
                if ($mode -eq "named") {
                    $publicFailures = 0
                    Write-CtmLog -RepoPath $RepoPath -Message "named public health check failed but tunnel process is still tracked:$statusCode $($_.Exception.Message)"
                } else {
                    $publicFailures += 1
                    Write-CtmLog -RepoPath $RepoPath -Message "public health check failed $publicFailures time(s):$statusCode $($_.Exception.Message)"
                }
            }
            $publicFailureLimit = [int]$Config["public_failure_restart_count"]
            if ($publicFailures -ge $publicFailureLimit) {
                Write-CtmLog -RepoPath $RepoPath -Message "public tunnel failed repeatedly; restarting tunnel"
                Stop-TrackedProcess -Process $cloudflaredProcess
                $cloudflaredProcess = $null
                $publicFailures = 0
                if ($mode -ne "named") {
                    $tunnelUrl = ""
                    $mcpUrl = ""
                }
            }
        }

        if ($mcpUrl) {
            Update-Session -Status "running" -Message "ready"
        } else {
            Update-Session -Status "starting" -Message "waiting for tunnel URL"
        }
    } catch {
        Write-CtmLog -RepoPath $RepoPath -Message "watcher error: $($_.Exception.Message)"
        Update-Session -Status "error" -Message $_.Exception.Message
    }

    Update-CtmKeepAwake
    Start-Sleep -Seconds $IntervalSeconds
}
