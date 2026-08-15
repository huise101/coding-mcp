$ErrorActionPreference = "Stop"

function Get-CtmPortableRoot {
    $skillDir = Split-Path -Parent $PSScriptRoot
    $skillsDir = Split-Path -Parent $skillDir
    return Split-Path -Parent $skillsDir
}

function Resolve-CtmRepoPath {
    param([string]$RepoPath)

    if ($RepoPath) {
        return (Resolve-Path -LiteralPath $RepoPath).Path
    }

    $candidate = Join-Path (Get-CtmPortableRoot) "coding-tools-mcp"
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "coding-tools-mcp repo not found. Pass -RepoPath or run Install-CodingToolsMcpRemote.ps1 first."
}

function Get-CtmRuntimeDir {
    param([string]$RepoPath)

    $runtimeDir = Join-Path $RepoPath ".runtime"
    if (-not (Test-Path -LiteralPath $runtimeDir)) {
        New-Item -ItemType Directory -Path $runtimeDir | Out-Null
    }
    return $runtimeDir
}

function Get-CtmConfigPath {
    param([string]$RepoPath)
    return (Join-Path (Get-CtmRuntimeDir -RepoPath $RepoPath) "chatgpt-mcp-config.json")
}

function Get-CtmSessionPath {
    param([string]$RepoPath)
    return (Join-Path (Get-CtmRuntimeDir -RepoPath $RepoPath) "chatgpt-mcp-last-session.txt")
}

function ConvertTo-CtmHashtable {
    param($Value)

    if ($null -eq $Value) {
        return @{}
    }
    if ($Value -is [hashtable]) {
        return $Value
    }
    $hash = @{}
    foreach ($property in $Value.PSObject.Properties) {
        $hash[$property.Name] = $property.Value
    }
    return $hash
}

function Read-CtmConfig {
    param([string]$RepoPath)

    $path = Get-CtmConfigPath -RepoPath $RepoPath
    if (-not (Test-Path -LiteralPath $path)) {
        return @{}
    }
    $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    if (-not $raw.Trim()) {
        return @{}
    }
    return ConvertTo-CtmHashtable ($raw | ConvertFrom-Json)
}

function Save-CtmConfig {
    param(
        [string]$RepoPath,
        [hashtable]$Config
    )

    $path = Get-CtmConfigPath -RepoPath $RepoPath
    ($Config | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 -LiteralPath $path
    return $path
}

function New-CtmUrlSafeToken {
    param([int]$ByteCount = 32)

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] $ByteCount
        $rng.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    } finally {
        $rng.Dispose()
    }
}

function New-CtmHexSecret {
    param([int]$ByteCount = 32)

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] $ByteCount
        $rng.GetBytes($bytes)
        return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $rng.Dispose()
    }
}

function Select-CtmWorkspace {
    param([string]$InitialPath)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select the workspace folder ChatGPT may operate on"
        $dialog.ShowNewFolderButton = $true
        if ($InitialPath -and (Test-Path -LiteralPath $InitialPath)) {
            $dialog.SelectedPath = (Resolve-Path -LiteralPath $InitialPath).Path
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    } catch {
        Write-Host "Folder picker is unavailable: $($_.Exception.Message)"
    }

    $typed = Read-Host "Workspace path"
    if (-not $typed) {
        throw "Workspace path is required."
    }
    return $typed
}

function Resolve-CtmWorkspace {
    param(
        [hashtable]$Config,
        [string]$WorkspacePath,
        [switch]$ChooseWorkspace
    )

    $initial = $WorkspacePath
    if (-not $initial -and $Config.ContainsKey("workspace_path")) {
        $initial = [string]$Config["workspace_path"]
    }
    if (-not $initial) {
        $initial = Get-CtmPortableRoot
    }
    if ($ChooseWorkspace) {
        $initial = Select-CtmWorkspace -InitialPath $initial
    }
    if (-not (Test-Path -LiteralPath $initial)) {
        throw "Workspace path does not exist: $initial"
    }
    return (Resolve-Path -LiteralPath $initial).Path
}

function Test-CtmPythonExe {
    param(
        [string]$Path,
        [string]$RepoPath = ""
    )

    if (-not $Path) {
        return $false
    }
    if ($Path -like "*\WindowsApps\python*.exe") {
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $output = & $Path -c "import sys; print(sys.version_info.major); print(sys.version_info.minor)" 2>$null
        if ($LASTEXITCODE -ne 0 -or $output.Count -lt 2) {
            return $false
        }
        $major = [int]$output[0]
        $minor = [int]$output[1]
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 11)) {
            return $false
        }
        if ($RepoPath) {
            $escapedRepoPath = $RepoPath.Replace("'", "''")
            $importOutput = & $Path -c "import sys; sys.path.insert(0, r'''$escapedRepoPath'''); import coding_tools_mcp; print('ok')" 2>$null
            if ($LASTEXITCODE -ne 0 -or -not ($importOutput -contains "ok")) {
                return $false
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Get-CtmPythonExe {
    param(
        [string]$RepoPath = "",
        [hashtable]$Config = @{}
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($Config -and $Config.ContainsKey("python_path") -and [string]$Config["python_path"]) {
        $candidates.Add([string]$Config["python_path"])
    }
    if ($env:CODING_TOOLS_MCP_PYTHON) {
        $candidates.Add($env:CODING_TOOLS_MCP_PYTHON)
    }
    if ($RepoPath) {
        foreach ($relative in @(".venv\Scripts\python.exe", "venv\Scripts\python.exe")) {
            $candidates.Add((Join-Path $RepoPath $relative))
        }
    }

    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) {
        $candidates.Add($cmd.Source)
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-CtmPythonExe -Path $candidate -RepoPath $RepoPath) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "A usable Python 3.11+ was not found. Set python_path in .runtime\chatgpt-mcp-config.json to a real python.exe, not the Microsoft Store WindowsApps alias."
}

function Get-CtmCloudflaredExe {
    param([string]$RepoPath)

    $local = Join-Path $RepoPath "tools\cloudflared.exe"
    if (Test-Path -LiteralPath $local) {
        return (Resolve-Path -LiteralPath $local).Path
    }
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    throw "cloudflared not found. Put cloudflared.exe in $RepoPath\tools or install Cloudflare cloudflared globally."
}

function Repair-CtmNamedTunnelConfig {
    param(
        [string]$RepoPath,
        [hashtable]$Config
    )

    if ($null -eq $Config) {
        return $false
    }

    $mode = ""
    if ($Config.ContainsKey("tunnel_mode")) {
        $mode = ([string]$Config["tunnel_mode"]).ToLowerInvariant()
    }
    $hasNamedState = $Config.ContainsKey("named_hostname") -or $Config.ContainsKey("named_tunnel_id") -or $Config.ContainsKey("named_config_path")
    if ($mode -ne "named" -and -not $hasNamedState) {
        return $false
    }

    $hostname = ""
    if ($Config.ContainsKey("named_hostname")) {
        $hostname = [string]$Config["named_hostname"]
    }
    if (-not $hostname) {
        return $false
    }

    $runtimeDir = Get-CtmRuntimeDir -RepoPath $RepoPath
    $tunnelDir = Join-Path $runtimeDir "cloudflared"
    if (-not (Test-Path -LiteralPath $tunnelDir -PathType Container)) {
        return $false
    }

    $changed = $false
    $tunnelId = ""
    if ($Config.ContainsKey("named_tunnel_id")) {
        $tunnelId = [string]$Config["named_tunnel_id"]
    }

    $credentialPath = ""
    if ($tunnelId) {
        $candidate = Join-Path $tunnelDir "$tunnelId.json"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $credentialPath = (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    if (-not $credentialPath) {
        $credentialFile = Get-ChildItem -LiteralPath $tunnelDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($credentialFile) {
            $credentialPath = $credentialFile.FullName
            $tunnelId = [System.IO.Path]::GetFileNameWithoutExtension($credentialFile.Name)
            if (-not $Config.ContainsKey("named_tunnel_id") -or [string]$Config["named_tunnel_id"] -ne $tunnelId) {
                $Config["named_tunnel_id"] = $tunnelId
                $changed = $true
            }
        }
    }
    if (-not $credentialPath -or -not $tunnelId) {
        return $changed
    }

    $port = 8767
    if ($Config.ContainsKey("port") -and [string]$Config["port"]) {
        $port = [int]$Config["port"]
    }
    $configPath = Join-Path $tunnelDir "config.yml"
    $yaml = @(
        "tunnel: $tunnelId",
        "credentials-file: $credentialPath",
        "ingress:",
        "  - hostname: $hostname",
        "    service: http://127.0.0.1:$port",
        "  - service: http_status:404"
    )
    $newConfigText = ($yaml -join [Environment]::NewLine) + [Environment]::NewLine
    $oldConfigText = ""
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $oldConfigText = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath
    }
    if ($oldConfigText -ne $newConfigText) {
        $yaml | Set-Content -Encoding UTF8 -LiteralPath $configPath
        $changed = $true
    }
    $resolvedConfigPath = (Resolve-Path -LiteralPath $configPath).Path
    if (-not $Config.ContainsKey("named_config_path") -or [string]$Config["named_config_path"] -ne $resolvedConfigPath) {
        $Config["named_config_path"] = $resolvedConfigPath
        $changed = $true
    }
    if (-not $Config.ContainsKey("tunnel_mode") -or ([string]$Config["tunnel_mode"]).ToLowerInvariant() -ne "named") {
        $Config["tunnel_mode"] = "named"
        $changed = $true
    }
    return $changed
}

function Get-CtmDevTunnelExe {
    param([string]$RepoPath)

    $local = Join-Path $RepoPath "tools\devtunnel.exe"
    if (Test-Path -LiteralPath $local) {
        return (Resolve-Path -LiteralPath $local).Path
    }
    $cmd = Get-Command devtunnel -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    throw "devtunnel not found. Put devtunnel.exe in $RepoPath\tools or install Microsoft Dev Tunnels CLI."
}

function Test-CtmLocalServer {
    param([int]$Port)

    try {
        $url = "http://127.0.0.1:$Port/.well-known/oauth-authorization-server"
        $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 3
        return ($response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Get-CtmPortOwner {
    param([int]$Port)

    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($conn) {
            return [int]$conn.OwningProcess
        }
    } catch {
    }
    $line = netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING\s+(\d+)" | Select-Object -First 1
    if ($line -and $line.Matches[0].Groups.Count -gt 1) {
        return [int]$line.Matches[0].Groups[1].Value
    }
    return $null
}

function Quote-CtmPowerShellString {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Start-CtmHiddenPowerShell {
    param(
        [string]$Command,
        [string]$WorkingDirectory
    )

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = "powershell.exe"
    $info.WorkingDirectory = $WorkingDirectory
    $info.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    return [System.Diagnostics.Process]::Start($info)
}

function Quote-CtmCommandArgument {
    param([string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Start-CtmNativeProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath,
        [hashtable]$Environment = @{}
    )

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.WorkingDirectory = $WorkingDirectory
    $info.Arguments = (($Arguments | ForEach-Object { Quote-CtmCommandArgument $_ }) -join " ")
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    if ($StdoutPath) {
        $info.RedirectStandardOutput = $true
    }
    if ($StderrPath) {
        $info.RedirectStandardError = $true
    }
    foreach ($key in $Environment.Keys) {
        $value = [string]$Environment[$key]
        if ($null -ne $info.EnvironmentVariables) {
            $info.EnvironmentVariables[$key] = $value
        } elseif ($null -ne $info.Environment) {
            $info.Environment[$key] = $value
        } else {
            throw "ProcessStartInfo does not expose an environment collection."
        }
    }
    $process = [System.Diagnostics.Process]::Start($info)
    if ($StdoutPath -or $StderrPath) {
        $eventAction = {
            if ($EventArgs.Data) {
                Add-Content -Encoding UTF8 -LiteralPath $Event.MessageData.Path -Value $EventArgs.Data
            }
        }
        if ($StdoutPath) {
            Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -SourceIdentifier "ctm-out-$($process.Id)" -MessageData @{ Path = $StdoutPath } -Action $eventAction | Out-Null
            $process.BeginOutputReadLine()
        }
        if ($StderrPath) {
            Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -SourceIdentifier "ctm-err-$($process.Id)" -MessageData @{ Path = $StderrPath } -Action $eventAction | Out-Null
            $process.BeginErrorReadLine()
        }
    }
    return $process
}

function Write-CtmSession {
    param(
        [string]$RepoPath,
        [hashtable]$Config,
        [string]$Status,
        [string]$TunnelUrl,
        [string]$McpUrl,
        [int]$WatcherPid = 0,
        [int]$ServerPid = 0,
        [int]$CloudflaredPid = 0,
        [string]$Message = ""
    )

    $runtimeDir = Get-CtmRuntimeDir -RepoPath $RepoPath
    $sessionPath = Get-CtmSessionPath -RepoPath $RepoPath
    $lines = @(
        "updated_at=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "status=$Status",
        "message=$Message",
        "workspace=$($Config["workspace_path"])",
        "port=$($Config["port"])",
        "tunnel_mode=$($Config["tunnel_mode"])",
        "watcher_pid=$WatcherPid",
        "server_pid=$ServerPid",
        "cloudflared_pid=$CloudflaredPid",
        "oauth_password=$($Config["oauth_password"])",
        "tunnel_url=$TunnelUrl",
        "mcp_url=$McpUrl",
        "config=$(Get-CtmConfigPath -RepoPath $RepoPath)",
        "watcher_log=$(Join-Path $runtimeDir 'watcher.log')",
        "server_stdout=$(Join-Path $runtimeDir 'mcp-server-last.stdout.log')",
        "server_stderr=$(Join-Path $runtimeDir 'mcp-server-last.stderr.log')",
        "cloudflared_stdout=$(Join-Path $runtimeDir 'cloudflared-last.stdout.log')",
        "cloudflared_stderr=$(Join-Path $runtimeDir 'cloudflared-last.stderr.log')"
    )
    $lines | Set-Content -Encoding UTF8 -LiteralPath $sessionPath
    return $sessionPath
}

function Write-CtmLog {
    param(
        [string]$RepoPath,
        [string]$Message
    )

    $logPath = Join-Path (Get-CtmRuntimeDir -RepoPath $RepoPath) "watcher.log"
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -Encoding UTF8 -LiteralPath $logPath -Value $line
}
