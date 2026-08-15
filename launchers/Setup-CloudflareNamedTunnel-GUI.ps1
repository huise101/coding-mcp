$ErrorActionPreference = "Stop"

$LauncherDir = Split-Path -Parent $PSCommandPath
$BasePath = Split-Path -Parent $LauncherDir
$RepoPath = Join-Path $BasePath "coding-tools-mcp"
$SkillScriptsPath = Join-Path $BasePath "skills\coding-tools-mcp-remote\scripts"
$NamedTunnelScript = Join-Path $SkillScriptsPath "New-CodingToolsMcpNamedTunnel.ps1"
$InstallScript = Join-Path $SkillScriptsPath "Install-CodingToolsMcpRemote.ps1"
$ConfigPath = Join-Path $RepoPath ".runtime\chatgpt-mcp-config.json"

function Quote-PsString {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-JsonValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return ""
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ""
    }
    return [string]$property.Value
}

function Read-LauncherConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }
    try {
        return (Get-Content -Raw -Encoding UTF8 -LiteralPath $ConfigPath | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-DefaultTunnelName {
    param([string]$Hostname)

    if ($null -eq $Hostname) {
        $Hostname = ""
    }
    $clean = $Hostname.Trim().TrimEnd("/")
    $clean = $clean -replace '^https?://', ''
    $clean = $clean -replace '/.*$', ''
    if ($clean -and $clean -ne "mcp.") {
        $label = ($clean -split '\.')[0]
    } else {
        $label = $env:COMPUTERNAME
    }
    $safe = $label.ToLowerInvariant() -replace '[^a-z0-9-]+', '-'
    $safe = $safe.Trim('-')
    if (-not $safe) {
        $safe = "device"
    }
    return "coding-tools-mcp-$safe"
}

function Validate-TunnelName {
    param([string]$Value)

    $clean = $Value.Trim()
    if ($clean -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{1,62}[A-Za-z0-9]$') {
        throw "Tunnel name must be 3-64 characters: letters, numbers, dot, underscore, or hyphen."
    }
    return $clean.ToLowerInvariant()
}

function Start-DetachedPowerShell {
    param([string]$Command)

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = "powershell.exe"
    $info.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $info.WorkingDirectory = $RepoPath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    return [System.Diagnostics.Process]::Start($info)
}

function Copy-Text {
    param([string]$Text)
    if ($Text) {
        [System.Windows.Forms.Clipboard]::SetText($Text)
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$config = Read-LauncherConfig
$workspace = Get-JsonValue -Object $config -Name "workspace_path"
if (-not $workspace) {
    $workspace = $RepoPath
}
$hostname = Get-JsonValue -Object $config -Name "named_hostname"
if (-not $hostname) {
    $hostname = "mcp."
}
$tunnelName = Get-JsonValue -Object $config -Name "named_tunnel_name"
if (-not $tunnelName) {
    $tunnelName = Get-DefaultTunnelName -Hostname $hostname
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Cloudflare Named Tunnel Setup"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(735, 405)

$hostLabel = New-Object System.Windows.Forms.Label
$hostLabel.Text = "Hostname"
$hostLabel.Location = New-Object System.Drawing.Point(18, 22)
$hostLabel.Size = New-Object System.Drawing.Size(120, 22)

$hostBox = New-Object System.Windows.Forms.TextBox
$hostBox.Location = New-Object System.Drawing.Point(145, 20)
$hostBox.Size = New-Object System.Drawing.Size(420, 24)
$hostBox.Text = $hostname

$tunnelLabel = New-Object System.Windows.Forms.Label
$tunnelLabel.Text = "Tunnel name"
$tunnelLabel.Location = New-Object System.Drawing.Point(18, 62)
$tunnelLabel.Size = New-Object System.Drawing.Size(120, 22)

$tunnelBox = New-Object System.Windows.Forms.TextBox
$tunnelBox.Location = New-Object System.Drawing.Point(145, 60)
$tunnelBox.Size = New-Object System.Drawing.Size(420, 24)
$tunnelBox.Text = $tunnelName

$tunnelHintLabel = New-Object System.Windows.Forms.Label
$tunnelHintLabel.Text = "Use a different hostname and tunnel name for each computer."
$tunnelHintLabel.Location = New-Object System.Drawing.Point(145, 86)
$tunnelHintLabel.Size = New-Object System.Drawing.Size(520, 18)

$workspaceLabel = New-Object System.Windows.Forms.Label
$workspaceLabel.Text = "Workspace folder"
$workspaceLabel.Location = New-Object System.Drawing.Point(18, 112)
$workspaceLabel.Size = New-Object System.Drawing.Size(120, 22)

$workspaceBox = New-Object System.Windows.Forms.TextBox
$workspaceBox.Location = New-Object System.Drawing.Point(145, 110)
$workspaceBox.Size = New-Object System.Drawing.Size(420, 24)
$workspaceBox.Text = $workspace

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse"
$browseButton.Location = New-Object System.Drawing.Point(582, 108)
$browseButton.Size = New-Object System.Drawing.Size(118, 28)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.Text = "Do not reuse one live hostname on multiple computers. Give each computer its own subdomain."
$noteLabel.Location = New-Object System.Drawing.Point(18, 155)
$noteLabel.Size = New-Object System.Drawing.Size(690, 26)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Status: ready"
$statusLabel.Location = New-Object System.Drawing.Point(18, 190)
$statusLabel.Size = New-Object System.Drawing.Size(690, 24)

$resultLabel = New-Object System.Windows.Forms.Label
$resultLabel.Text = "Final MCP URL"
$resultLabel.Location = New-Object System.Drawing.Point(18, 235)
$resultLabel.Size = New-Object System.Drawing.Size(120, 22)

$resultBox = New-Object System.Windows.Forms.TextBox
$resultBox.Location = New-Object System.Drawing.Point(145, 232)
$resultBox.Size = New-Object System.Drawing.Size(420, 24)
$resultBox.ReadOnly = $true
$resultBox.Text = ""
if ($hostname -and $hostname -ne "mcp.") {
    $resultBox.Text = "https://$hostname/mcp"
}

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = "Copy URL"
$copyButton.Location = New-Object System.Drawing.Point(582, 230)
$copyButton.Size = New-Object System.Drawing.Size(118, 28)

$setupButton = New-Object System.Windows.Forms.Button
$setupButton.Text = "Configure Tunnel"
$setupButton.Location = New-Object System.Drawing.Point(145, 315)
$setupButton.Size = New-Object System.Drawing.Size(145, 34)

$startupButton = New-Object System.Windows.Forms.Button
$startupButton.Text = "Install Startup"
$startupButton.Location = New-Object System.Drawing.Point(305, 315)
$startupButton.Size = New-Object System.Drawing.Size(125, 34)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(445, 315)
$closeButton.Size = New-Object System.Drawing.Size(95, 34)

$script:SetupProcess = $null
$script:StartupProcess = $null
$script:TunnelNameTouched = [bool](Get-JsonValue -Object $config -Name "named_tunnel_name")
$script:UpdatingTunnelName = $false
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 1500

function Validate-Hostname {
    param([string]$Value)

    $clean = $Value.Trim().TrimEnd("/")
    $clean = $clean -replace '^https?://', ''
    $clean = $clean -replace '/.*$', ''
    if ($clean -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$') {
        throw "Enter a real hostname, for example: mcp.example.com"
    }
    if ($clean -notmatch '^mcp\.') {
        $answer = [System.Windows.Forms.MessageBox]::Show($form, "Recommended hostname starts with mcp. Continue with '$clean'?", "Cloudflare Named Tunnel", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return ""
        }
    }
    return $clean.ToLowerInvariant()
}

$pollTimer.Add_Tick({
    $setupRunning = ($script:SetupProcess -and -not $script:SetupProcess.HasExited)
    $startupRunning = ($script:StartupProcess -and -not $script:StartupProcess.HasExited)

    $setupButton.Enabled = -not $setupRunning -and -not $startupRunning
    $startupButton.Enabled = -not $setupRunning -and -not $startupRunning

    if ($setupRunning) {
        $statusLabel.Text = "Status: configuring; finish the Cloudflare browser login if it opened"
        return
    }
    if ($startupRunning) {
        $statusLabel.Text = "Status: installing startup task..."
        return
    }

    if ($script:SetupProcess) {
        $stdout = $script:SetupProcess.StandardOutput.ReadToEnd()
        $stderr = $script:SetupProcess.StandardError.ReadToEnd()
        $exitCode = $script:SetupProcess.ExitCode
        $script:SetupProcess.Dispose()
        $script:SetupProcess = $null
        if ($exitCode -eq 0) {
            $statusLabel.Text = "Status: named tunnel configured"
            $resultBox.Text = "https://$($hostBox.Text.Trim())/mcp"
        } else {
            $detail = ($stderr + "`r`n" + $stdout).Trim()
            if ($detail.Length -gt 2000) {
                $detail = $detail.Substring(0, 2000)
            }
            $statusLabel.Text = "Status: setup failed"
            [System.Windows.Forms.MessageBox]::Show($form, $detail, "Cloudflare Named Tunnel", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        $pollTimer.Stop()
        return
    }

    if ($script:StartupProcess) {
        $stdout = $script:StartupProcess.StandardOutput.ReadToEnd()
        $stderr = $script:StartupProcess.StandardError.ReadToEnd()
        $exitCode = $script:StartupProcess.ExitCode
        $script:StartupProcess.Dispose()
        $script:StartupProcess = $null
        if ($exitCode -eq 0) {
            $statusLabel.Text = "Status: startup task installed"
        } else {
            $detail = ($stderr + "`r`n" + $stdout).Trim()
            if ($detail.Length -gt 2000) {
                $detail = $detail.Substring(0, 2000)
            }
            $statusLabel.Text = "Status: startup install failed"
            [System.Windows.Forms.MessageBox]::Show($form, $detail, "Cloudflare Named Tunnel", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        $pollTimer.Stop()
    }
})

$hostBox.Add_TextChanged({
    $value = $hostBox.Text.Trim()
    $value = $value -replace '^https?://', ''
    $value = $value -replace '/.*$', ''
    if (-not $script:TunnelNameTouched) {
        $script:UpdatingTunnelName = $true
        try {
            $tunnelBox.Text = Get-DefaultTunnelName -Hostname $value
        } finally {
            $script:UpdatingTunnelName = $false
        }
    }
    if ($value -and $value -ne "mcp.") {
        $resultBox.Text = "https://$value/mcp"
    } else {
        $resultBox.Text = ""
    }
})

$tunnelBox.Add_TextChanged({
    if (-not $script:UpdatingTunnelName) {
        $script:TunnelNameTouched = $true
    }
})

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select workspace folder"
    $dialog.ShowNewFolderButton = $true
    if ($workspaceBox.Text -and (Test-Path -LiteralPath $workspaceBox.Text -PathType Container)) {
        $dialog.SelectedPath = (Resolve-Path -LiteralPath $workspaceBox.Text).Path
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $workspaceBox.Text = $dialog.SelectedPath
    }
})

$copyButton.Add_Click({
    Copy-Text -Text $resultBox.Text
    $statusLabel.Text = "Status: URL copied"
})

$setupButton.Add_Click({
    try {
        $cleanHost = Validate-Hostname -Value $hostBox.Text
        if (-not $cleanHost) {
            return
        }
        $cleanTunnelName = Validate-TunnelName -Value $tunnelBox.Text
        $workspace = $workspaceBox.Text.Trim()
        if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
            throw "Workspace folder does not exist: $workspace"
        }
        $hostBox.Text = $cleanHost
        $tunnelBox.Text = $cleanTunnelName
        $resultBox.Text = "https://$cleanHost/mcp"
        $statusLabel.Text = "Status: launching Cloudflare setup..."
        [System.Windows.Forms.Application]::DoEvents()

        $command = "& $(Quote-PsString $NamedTunnelScript) -RepoPath $(Quote-PsString $RepoPath) -WorkspacePath $(Quote-PsString $workspace) -Hostname $(Quote-PsString $cleanHost) -TunnelName $(Quote-PsString $cleanTunnelName) -OverwriteDns"
        $script:SetupProcess = Start-DetachedPowerShell -Command $command
        $setupButton.Enabled = $false
        $startupButton.Enabled = $false
        $pollTimer.Start()
    } catch {
        $statusLabel.Text = "Status: error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Cloudflare Named Tunnel", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$startupButton.Add_Click({
    try {
        $workspace = $workspaceBox.Text.Trim()
        if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
            throw "Workspace folder does not exist: $workspace"
        }
        $statusLabel.Text = "Status: installing startup task..."
        [System.Windows.Forms.Application]::DoEvents()
        $command = "& $(Quote-PsString $InstallScript) -RepoPath $(Quote-PsString $RepoPath) -WorkspacePath $(Quote-PsString $workspace) -TunnelMode named -InstallStartupTask -SkipPythonInstall"
        $script:StartupProcess = Start-DetachedPowerShell -Command $command
        $setupButton.Enabled = $false
        $startupButton.Enabled = $false
        $pollTimer.Start()
    } catch {
        $statusLabel.Text = "Status: error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Cloudflare Named Tunnel", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$closeButton.Add_Click({
    $form.Close()
})

$form.Controls.AddRange(@(
    $hostLabel,
    $hostBox,
    $tunnelLabel,
    $tunnelBox,
    $tunnelHintLabel,
    $workspaceLabel,
    $workspaceBox,
    $browseButton,
    $noteLabel,
    $statusLabel,
    $resultLabel,
    $resultBox,
    $copyButton,
    $setupButton,
    $startupButton,
    $closeButton
))

[void]$form.ShowDialog()
