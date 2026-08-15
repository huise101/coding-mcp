$ErrorActionPreference = "Stop"

$LauncherDir = Split-Path -Parent $PSCommandPath
$BasePath = Split-Path -Parent $LauncherDir
$RepoPath = Join-Path $BasePath "coding-tools-mcp"
$SkillScriptsPath = Join-Path $BasePath "skills\coding-tools-mcp-remote\scripts"
$StartScript = Join-Path $SkillScriptsPath "Start-CodingToolsMcpRemote.ps1"
$StopScript = Join-Path $SkillScriptsPath "Stop-CodingToolsMcpRemote.ps1"
$ConfigPath = Join-Path $RepoPath ".runtime\chatgpt-mcp-config.json"
$SessionPath = Join-Path $RepoPath ".runtime\chatgpt-mcp-last-session.txt"
$ActiveTargetPath = Join-Path $RepoPath ".runtime\chatgpt-mcp-active-target.json"
$RemoteRoot = Join-Path $BasePath ".codex-remote"
$RemoteProfilesDir = Join-Path $RemoteRoot "profiles"
$RemoteSecretsDir = Join-Path $RemoteRoot "secrets"
$RemoteInvokeScript = Join-Path $BasePath "skills\windows-remote-server\scripts\invoke_remote.ps1"

function Quote-PsString {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Quote-RemoteShellString {
    param([string]$Value)

    if ($null -eq $Value) {
        $Value = ""
    }
    return "'" + $Value.Replace("'", "'\''") + "'"
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

function Read-LauncherSession {
    $values = @{}
    if (-not (Test-Path -LiteralPath $SessionPath)) {
        return $values
    }
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $SessionPath) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

function Get-ConnectionInfo {
    $config = Read-LauncherConfig
    $session = Read-LauncherSession

    $workspace = Get-JsonValue -Object $config -Name "workspace_path"
    $password = Get-JsonValue -Object $config -Name "oauth_password"
    $status = ""
    $mcpUrl = ""

    if ($session.ContainsKey("workspace") -and $session["workspace"]) {
        $workspace = $session["workspace"]
    }
    if ($session.ContainsKey("oauth_password") -and $session["oauth_password"]) {
        $password = $session["oauth_password"]
    }
    if ($session.ContainsKey("status")) {
        $status = $session["status"]
    }
    if ($session.ContainsKey("mcp_url") -and $session["mcp_url"]) {
        $mcpUrl = $session["mcp_url"]
    }

    if (-not $mcpUrl) {
        $tunnelMode = Get-JsonValue -Object $config -Name "tunnel_mode"
        $namedHostname = Get-JsonValue -Object $config -Name "named_hostname"
        $devtunnelUrl = Get-JsonValue -Object $config -Name "devtunnel_url"
        if (($tunnelMode -eq "named" -or -not $devtunnelUrl) -and $namedHostname) {
            $mcpUrl = "https://$namedHostname/mcp"
        }
        elseif ($devtunnelUrl) {
            $mcpUrl = $devtunnelUrl.TrimEnd("/") + "/mcp"
        }
    }
    if (-not $workspace) {
        $workspace = $RepoPath
    }

    return [pscustomobject]@{
        Workspace = $workspace
        McpUrl = $mcpUrl
        Password = $password
        Status = $status
    }
}

function Read-ActiveTarget {
    if (-not (Test-Path -LiteralPath $ActiveTargetPath)) {
        return [pscustomobject]@{
            mode = "local"
            workspace_path = ""
            remote_profile = ""
            remote_folder = ""
            ssh_connection = ""
            updated_at = ""
        }
    }
    try {
        return (Get-Content -Raw -Encoding UTF8 -LiteralPath $ActiveTargetPath | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{
            mode = "local"
            workspace_path = ""
            remote_profile = ""
            remote_folder = ""
            ssh_connection = ""
            updated_at = ""
        }
    }
}

function Write-ActiveTarget {
    param(
        [ValidateSet("local", "remote", "unselected")][string]$Mode,
        [string]$WorkspacePath = "",
        [string]$RemoteProfile = "",
        [string]$RemoteFolder = "",
        [string]$SshConnection = ""
    )

    $runtimeDir = Split-Path -Parent $ActiveTargetPath
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    $target = [ordered]@{
        mode = $Mode
        remote_profile = $RemoteProfile
        remote_folder = $RemoteFolder
        ssh_connection = $SshConnection
        updated_at = (Get-Date).ToString("s")
    }
    if ($Mode -eq "remote") {
        $target["local_host_workspace_path"] = $WorkspacePath
    }
    elseif ($Mode -eq "unselected") {
        $target["local_host_workspace_path"] = $WorkspacePath
    }
    else {
        $target["workspace_path"] = $WorkspacePath
    }
    $target | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ActiveTargetPath -Encoding UTF8
    return [pscustomobject]$target
}

function ConvertTo-EnvValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ""
    }
    return ($Value -replace "(`r|`n)", "").Trim()
}

function Read-RemoteEnvFile {
    param([string]$Profile)

    $values = @{}
    $path = Join-Path $RemoteProfilesDir "$Profile.env"
    if (-not (Test-Path -LiteralPath $path)) {
        return $values
    }
    foreach ($rawLine in Get-Content -Encoding UTF8 -LiteralPath $path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            continue
        }
        $index = $line.IndexOf("=")
        $key = $line.Substring(0, $index).Trim()
        $value = $line.Substring($index + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }
    return $values
}

function Get-RemoteProfileInfo {
    $profile = ""
    if (Test-Path -LiteralPath $RemoteProfilesDir) {
        $latest = Get-ChildItem -LiteralPath $RemoteProfilesDir -Filter "*.env" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latest) {
            $profile = [System.IO.Path]::GetFileNameWithoutExtension($latest.Name)
        }
    }

    $envValues = Read-RemoteEnvFile -Profile $profile
    $hostName = ""
    $port = "22"
    $userName = ""
    $remoteWorkdir = ""
    if ($envValues.ContainsKey("REMOTE_HOST")) {
        $hostName = $envValues["REMOTE_HOST"]
    }
    if ($envValues.ContainsKey("REMOTE_PORT") -and $envValues["REMOTE_PORT"]) {
        $port = $envValues["REMOTE_PORT"]
    }
    if ($envValues.ContainsKey("REMOTE_USER") -and $envValues["REMOTE_USER"]) {
        $userName = $envValues["REMOTE_USER"]
    }
    if ($envValues.ContainsKey("REMOTE_WORKDIR") -and $envValues["REMOTE_WORKDIR"]) {
        $remoteWorkdir = $envValues["REMOTE_WORKDIR"]
    }

    $sshConnection = ""
    if ($hostName) {
        $sshConnection = "ssh -p $port $userName@$hostName"
    }

    return [pscustomobject]@{
        Profile = $profile
        SshConnection = $sshConnection
        RemoteFolder = $remoteWorkdir
        Host = $hostName
        Port = $port
        User = $userName
    }
}

function Normalize-RemoteFolder {
    param(
        [string]$Path,
        [switch]$AllowEmpty
    )

    $folder = ""
    if ($null -ne $Path) {
        $folder = $Path.Trim().Replace("\", "/")
    }
    if (-not $folder) {
        if ($AllowEmpty) {
            return ""
        }
        throw "Remote folder is required. Choose a concrete project folder such as /path/to/project."
    }
    if ($folder -eq "/" -or $folder -eq "~" -or $folder -like "~/*") {
        throw "Remote folder '$folder' is not allowed. Choose a concrete project folder such as /path/to/project."
    }
    if (-not $folder.StartsWith("/")) {
        throw "Remote folder must be an absolute Linux path, for example /path/to/project."
    }
    while ($folder.Contains("//")) {
        $folder = $folder.Replace("//", "/")
    }
    if ($folder.Length -gt 1) {
        $folder = $folder.TrimEnd("/")
    }
    if ($folder -eq "/") {
        throw "Remote folder '/' is not allowed. Choose a concrete project folder such as /path/to/project."
    }
    return $folder
}

function Parse-SshConnection {
    param([string]$Text)

    $raw = ""
    if ($null -ne $Text) {
        $raw = $Text.Trim()
    }
    if (-not $raw) {
        throw "SSH connection is required. Example: ssh -p <port> user@host"
    }

    $port = "22"
    if ($raw -match '(?i)(^|\s)-p\s+(\d+)') {
        $port = $Matches[2]
        $raw = [regex]::Replace($raw, '(?i)(^|\s)-p\s+\d+', ' ')
    }
    $raw = [regex]::Replace($raw, '^\s*ssh(\.exe)?\s+', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim()
    $tokens = $raw -split '\s+' | Where-Object { $_ }
    $target = ""
    foreach ($token in $tokens) {
        $clean = $token.Trim('"', "'")
        if ($clean -like "*@*" -or (-not $clean.StartsWith("-"))) {
            $target = $clean
        }
    }
    if (-not $target -or $target.StartsWith("-")) {
        throw "Could not find SSH target. Use: ssh -p <port> user@host"
    }

    if ($target -notmatch '^([^@]+)@(.+)$') {
        throw "SSH target must include user@host."
    }
    $userName = $Matches[1]
    $hostPart = $Matches[2]
    if ($hostPart -match '^(.+):(\d+)$' -and $hostPart -notmatch '^\[.*\]') {
        $hostPart = $Matches[1]
        $port = $Matches[2]
    }
    $hostName = $hostPart.Trim('[', ']')
    if (-not $userName -or -not $hostName -or $port -notmatch '^\d+$') {
        throw "Invalid SSH connection. Example: ssh -p <port> user@host"
    }

    return [pscustomobject]@{
        User = $userName
        Host = $hostName
        Port = $port
    }
}

function Save-RemoteProfile {
    param(
        [string]$Profile,
        [string]$SshConnection,
        [string]$Password,
        [string]$RemoteFolder
    )

    $profileName = ""
    if ($null -ne $Profile) {
        $profileName = $Profile.Trim()
    }
    if (-not $profileName) {
        throw "Remote profile name is required."
    }
    if ($profileName -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid profile name. Use letters, digits, dot, underscore, or hyphen only."
    }
    $parsed = Parse-SshConnection -Text $SshConnection
    $workdir = Normalize-RemoteFolder -Path $RemoteFolder -AllowEmpty

    New-Item -ItemType Directory -Force -Path $RemoteProfilesDir, $RemoteSecretsDir | Out-Null
    $profilePath = Join-Path $RemoteProfilesDir "$profileName.env"
    $credentialPath = Join-Path $RemoteSecretsDir "$profileName.credential.xml"

    $lines = @(
        "# Local profile for windows-remote-server. Do not commit this file.",
        "REMOTE_HOST=$(ConvertTo-EnvValue $parsed.Host)",
        "REMOTE_PORT=$(ConvertTo-EnvValue $parsed.Port)",
        "REMOTE_USER=$(ConvertTo-EnvValue $parsed.User)"
    )
    if ($workdir) {
        $lines += "REMOTE_WORKDIR=$(ConvertTo-EnvValue $workdir)"
    }

    if ($Password) {
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($parsed.User, $securePassword)
        $credential | Export-Clixml -LiteralPath $credentialPath
        $lines += "REMOTE_CREDENTIAL_XML=secrets/$profileName.credential.xml"
    }
    elseif (Test-Path -LiteralPath $credentialPath) {
        $lines += "REMOTE_CREDENTIAL_XML=secrets/$profileName.credential.xml"
    }
    else {
        throw "SSH password is required the first time you save this profile."
    }

    Set-Content -LiteralPath $profilePath -Value $lines -Encoding UTF8
    return [pscustomobject]@{
        Profile = $profileName
        User = $parsed.User
        Host = $parsed.Host
        Port = $parsed.Port
        RemoteFolder = $workdir
    }
}

function Get-RemotePythonPath {
    $config = Read-LauncherConfig
    $configured = Get-JsonValue -Object $config -Name "python_path"
    if ($configured) {
        return $configured
    }
    if (Test-Path -LiteralPath "D:\Anaconda\python.exe") {
        return "D:\Anaconda\python.exe"
    }
    return "python"
}

function Invoke-RemoteProfileCommand {
    param(
        [string]$Profile,
        [string]$RemoteCommand,
        [int]$TimeoutSeconds = 35
    )

    $command = "& $(Quote-PsString $RemoteInvokeScript) -Profile $(Quote-PsString $Profile) -Root $(Quote-PsString $RemoteRoot) -Python $(Quote-PsString (Get-RemotePythonPath)) -Command $(Quote-PsString $RemoteCommand)"
    $result = Invoke-HiddenPowerShell -Command $command -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitCode -ne 0) {
        throw (($result.Stderr + "`n" + $result.Stdout).Trim())
    }
    return $result
}

function Join-RemotePath {
    param(
        [string]$BasePath,
        [string]$ChildName
    )

    $base = ""
    if ($null -ne $BasePath) {
        $base = $BasePath.Trim()
    }
    $child = ""
    if ($null -ne $ChildName) {
        $child = $ChildName.Trim("/")
    }
    if (-not $base -or $base -eq "/") {
        return "/" + $child
    }
    return $base.TrimEnd("/") + "/" + $child
}

function Get-RemoteParentPath {
    param([string]$Path)

    $pathText = "/"
    if ($null -ne $Path -and $Path.Trim()) {
        $pathText = $Path.Trim()
    }
    if (-not $pathText -or $pathText -eq "/") {
        return "/"
    }
    $trimmed = $pathText.TrimEnd("/")
    $index = $trimmed.LastIndexOf("/")
    if ($index -le 0) {
        return "/"
    }
    return $trimmed.Substring(0, $index)
}

function Get-RemoteDirectoryListing {
    param(
        [string]$Profile,
        [string]$RemotePath
    )

    $path = ""
    if ($null -ne $RemotePath) {
        $path = $RemotePath.Trim()
    }
    if (-not $path) {
        $path = "/"
    }
    $quotedPath = Quote-RemoteShellString $path
    $remoteCommand = 'cd ' + $quotedPath + ' 2>/dev/null || exit 4; echo "__PWD__:$PWD"; for d in ./* ./.[!.]* ./..?*; do [ -d "$d" ] || continue; b="${d#./}"; [ "$b" = "." ] && continue; [ "$b" = ".." ] && continue; echo "__DIR__:$b"; done | sort'
    $result = Invoke-RemoteProfileCommand -Profile $Profile -RemoteCommand $remoteCommand -TimeoutSeconds 35
    $pwd = $path
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($result.Stdout -split "`r?`n")) {
        if ($line.StartsWith("__PWD__:")) {
            $pwd = $line.Substring(8)
        }
        elseif ($line.StartsWith("__DIR__:")) {
            $name = $line.Substring(8)
            if ($name) {
                [void]$dirs.Add($name)
            }
        }
    }
    return [pscustomobject]@{
        Path = $pwd
        Directories = $dirs
    }
}

function Invoke-HiddenPowerShell {
    param(
        [string]$Command,
        [int]$TimeoutSeconds = 120
    )

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

    $process = [System.Diagnostics.Process]::Start($info)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $process.Kill()
        } catch {
        }
        throw "The command timed out after $TimeoutSeconds seconds."
    }
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.Result
        Stderr = $stderrTask.Result
    }
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

function Show-RemoteFolderBrowser {
    param(
        [string]$Profile,
        [string]$StartPath,
        $Owner
    )

    $initialPath = "/"
    if ($null -ne $StartPath -and $StartPath.Trim()) {
        $initialPath = $StartPath.Trim()
    }

    $browser = New-Object System.Windows.Forms.Form
    $browser.Text = "Select Remote Folder"
    $browser.StartPosition = "CenterParent"
    $browser.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $browser.MaximizeBox = $false
    $browser.MinimizeBox = $false
    $browser.ClientSize = New-Object System.Drawing.Size(640, 470)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = "Current remote folder"
    $pathLabel.Location = New-Object System.Drawing.Point(16, 18)
    $pathLabel.Size = New-Object System.Drawing.Size(150, 22)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(170, 16)
    $pathBox.Size = New-Object System.Drawing.Size(450, 24)
    $pathBox.ReadOnly = $true

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(16, 56)
    $listBox.Size = New-Object System.Drawing.Size(604, 300)
    $listBox.IntegralHeight = $false

    $status = New-Object System.Windows.Forms.Label
    $status.Text = "Ready"
    $status.Location = New-Object System.Drawing.Point(16, 368)
    $status.Size = New-Object System.Drawing.Size(604, 24)

    $upButton = New-Object System.Windows.Forms.Button
    $upButton.Text = "Up"
    $upButton.Location = New-Object System.Drawing.Point(16, 410)
    $upButton.Size = New-Object System.Drawing.Size(80, 32)

    $refreshRemoteButton = New-Object System.Windows.Forms.Button
    $refreshRemoteButton.Text = "Refresh"
    $refreshRemoteButton.Location = New-Object System.Drawing.Point(108, 410)
    $refreshRemoteButton.Size = New-Object System.Drawing.Size(95, 32)

    $openButton = New-Object System.Windows.Forms.Button
    $openButton.Text = "Open"
    $openButton.Location = New-Object System.Drawing.Point(215, 410)
    $openButton.Size = New-Object System.Drawing.Size(95, 32)

    $selectButton = New-Object System.Windows.Forms.Button
    $selectButton.Text = "Select This Folder"
    $selectButton.Location = New-Object System.Drawing.Point(380, 410)
    $selectButton.Size = New-Object System.Drawing.Size(135, 32)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(525, 410)
    $cancelButton.Size = New-Object System.Drawing.Size(95, 32)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $browser.Controls.AddRange(@(
        $pathLabel,
        $pathBox,
        $listBox,
        $status,
        $upButton,
        $refreshRemoteButton,
        $openButton,
        $selectButton,
        $cancelButton
    ))
    $browser.CancelButton = $cancelButton

    $state = @{
        CurrentPath = $initialPath
        SelectedPath = ""
    }

    function Load-RemoteFolder {
        param([string]$Path)

        try {
            $browser.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            $status.Text = "Loading remote folders..."
            [System.Windows.Forms.Application]::DoEvents()

            $listing = Get-RemoteDirectoryListing -Profile $Profile -RemotePath $Path
            $state.CurrentPath = $listing.Path
            $pathBox.Text = $listing.Path
            $listBox.Items.Clear()
            foreach ($dir in $listing.Directories) {
                [void]$listBox.Items.Add($dir)
            }
            $listBox.ClearSelected()
            $status.Text = "$($listBox.Items.Count) folder(s). Select a folder, or click Select with nothing highlighted to choose the current folder."
        } catch {
            $status.Text = "Load failed"
            [System.Windows.Forms.MessageBox]::Show(
                $browser,
                $_.Exception.Message,
                "Remote folder browser",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        } finally {
            $browser.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }

    function Open-SelectedRemoteFolder {
        if ($listBox.SelectedItem) {
            $childPath = Join-RemotePath -BasePath $state.CurrentPath -ChildName ([string]$listBox.SelectedItem)
            Load-RemoteFolder -Path $childPath
        }
    }

    $upButton.Add_Click({
        Load-RemoteFolder -Path (Get-RemoteParentPath -Path $state.CurrentPath)
    })
    $refreshRemoteButton.Add_Click({
        Load-RemoteFolder -Path $state.CurrentPath
    })
    $openButton.Add_Click({
        Open-SelectedRemoteFolder
    })
    $listBox.Add_DoubleClick({
        Open-SelectedRemoteFolder
    })
    $listBox.Add_SelectedIndexChanged({
        if ($listBox.SelectedItem) {
            $status.Text = "Selected: $(Join-RemotePath -BasePath $state.CurrentPath -ChildName ([string]$listBox.SelectedItem))"
        }
    })
    $selectButton.Add_Click({
        if ($listBox.SelectedItem) {
            $state.SelectedPath = Join-RemotePath -BasePath $state.CurrentPath -ChildName ([string]$listBox.SelectedItem)
        }
        else {
            $state.SelectedPath = $state.CurrentPath
        }
        $browser.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $browser.Close()
    })

    $browser.Add_Shown({
        Load-RemoteFolder -Path $initialPath
    })
    if ($Owner) {
        $dialogResult = $browser.ShowDialog($Owner)
    }
    else {
        $dialogResult = $browser.ShowDialog()
    }
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $state.SelectedPath
    }
    return ""
}

$info = Get-ConnectionInfo
$remoteInfo = [pscustomobject]@{
    Profile = ""
    SshConnection = ""
    RemoteFolder = ""
    Host = ""
    Port = ""
    User = ""
}
$activeTarget = Write-ActiveTarget -Mode unselected -WorkspacePath $info.Workspace

$form = New-Object System.Windows.Forms.Form
$form.Text = "Coding MCP Launcher"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 535)

$workspaceLabel = New-Object System.Windows.Forms.Label
$workspaceLabel.Text = "Local target"
$workspaceLabel.Location = New-Object System.Drawing.Point(18, 22)
$workspaceLabel.Size = New-Object System.Drawing.Size(120, 22)

$workspaceBox = New-Object System.Windows.Forms.TextBox
$workspaceBox.Location = New-Object System.Drawing.Point(145, 20)
$workspaceBox.Size = New-Object System.Drawing.Size(445, 24)
$workspaceBox.Text = ""

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse"
$browseButton.Location = New-Object System.Drawing.Point(610, 18)
$browseButton.Size = New-Object System.Drawing.Size(120, 28)

$activeTargetLabel = New-Object System.Windows.Forms.Label
$activeTargetLabel.Text = "Target: not selected"
$activeTargetLabel.Location = New-Object System.Drawing.Point(18, 62)
$activeTargetLabel.Size = New-Object System.Drawing.Size(712, 26)
$activeTargetLabel.Font = New-Object System.Drawing.Font($activeTargetLabel.Font.FontFamily, 9, [System.Drawing.FontStyle]::Bold)

$useLocalButton = New-Object System.Windows.Forms.Button
$useLocalButton.Text = "Use Local Target"
$useLocalButton.Location = New-Object System.Drawing.Point(145, 92)
$useLocalButton.Size = New-Object System.Drawing.Size(150, 32)

$useRemoteButton = New-Object System.Windows.Forms.Button
$useRemoteButton.Text = "Use Remote Target"
$useRemoteButton.Location = New-Object System.Drawing.Point(312, 92)
$useRemoteButton.Size = New-Object System.Drawing.Size(160, 32)

$remoteProfileLabel = New-Object System.Windows.Forms.Label
$remoteProfileLabel.Text = "Remote profile"
$remoteProfileLabel.Location = New-Object System.Drawing.Point(18, 142)
$remoteProfileLabel.Size = New-Object System.Drawing.Size(120, 22)

$remoteProfileBox = New-Object System.Windows.Forms.TextBox
$remoteProfileBox.Location = New-Object System.Drawing.Point(145, 140)
$remoteProfileBox.Size = New-Object System.Drawing.Size(130, 24)
$remoteProfileBox.Text = $remoteInfo.Profile

$remoteSummaryLabel = New-Object System.Windows.Forms.Label
$remoteSummaryLabel.Text = "Remote: not saved"
if ($remoteInfo.Host) {
    $remoteSummaryLabel.Text = "Remote: $($remoteInfo.User)@$($remoteInfo.Host):$($remoteInfo.Port) $($remoteInfo.RemoteFolder)"
}
$remoteSummaryLabel.Location = New-Object System.Drawing.Point(288, 142)
$remoteSummaryLabel.Size = New-Object System.Drawing.Size(442, 22)

$sshLabel = New-Object System.Windows.Forms.Label
$sshLabel.Text = "SSH connection"
$sshLabel.Location = New-Object System.Drawing.Point(18, 180)
$sshLabel.Size = New-Object System.Drawing.Size(120, 22)

$sshBox = New-Object System.Windows.Forms.TextBox
$sshBox.Location = New-Object System.Drawing.Point(145, 178)
$sshBox.Size = New-Object System.Drawing.Size(445, 24)
$sshBox.Text = $remoteInfo.SshConnection

$saveRemoteButton = New-Object System.Windows.Forms.Button
$saveRemoteButton.Text = "Save Remote"
$saveRemoteButton.Location = New-Object System.Drawing.Point(610, 176)
$saveRemoteButton.Size = New-Object System.Drawing.Size(120, 28)

$sshPasswordLabel = New-Object System.Windows.Forms.Label
$sshPasswordLabel.Text = "SSH password"
$sshPasswordLabel.Location = New-Object System.Drawing.Point(18, 218)
$sshPasswordLabel.Size = New-Object System.Drawing.Size(120, 22)

$sshPasswordBox = New-Object System.Windows.Forms.TextBox
$sshPasswordBox.Location = New-Object System.Drawing.Point(145, 216)
$sshPasswordBox.Size = New-Object System.Drawing.Size(445, 24)
$sshPasswordBox.UseSystemPasswordChar = $true

$testRemoteButton = New-Object System.Windows.Forms.Button
$testRemoteButton.Text = "Test Remote"
$testRemoteButton.Location = New-Object System.Drawing.Point(610, 214)
$testRemoteButton.Size = New-Object System.Drawing.Size(120, 28)

$remoteFolderLabel = New-Object System.Windows.Forms.Label
$remoteFolderLabel.Text = "Remote folder"
$remoteFolderLabel.Location = New-Object System.Drawing.Point(18, 256)
$remoteFolderLabel.Size = New-Object System.Drawing.Size(120, 22)

$remoteFolderBox = New-Object System.Windows.Forms.TextBox
$remoteFolderBox.Location = New-Object System.Drawing.Point(145, 254)
$remoteFolderBox.Size = New-Object System.Drawing.Size(330, 24)
$remoteFolderBox.Text = $remoteInfo.RemoteFolder

$browseRemoteButton = New-Object System.Windows.Forms.Button
$browseRemoteButton.Text = "Browse Remote"
$browseRemoteButton.Location = New-Object System.Drawing.Point(485, 252)
$browseRemoteButton.Size = New-Object System.Drawing.Size(105, 28)

$remoteFolderHintLabel = New-Object System.Windows.Forms.Label
$remoteFolderHintLabel.Text = "required; not /"
$remoteFolderHintLabel.Location = New-Object System.Drawing.Point(610, 256)
$remoteFolderHintLabel.Size = New-Object System.Drawing.Size(140, 22)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Status: choose a target for this run"
$statusLabel.Location = New-Object System.Drawing.Point(18, 300)
$statusLabel.Size = New-Object System.Drawing.Size(712, 24)

$urlLabel = New-Object System.Windows.Forms.Label
$urlLabel.Text = "MCP URL"
$urlLabel.Location = New-Object System.Drawing.Point(18, 350)
$urlLabel.Size = New-Object System.Drawing.Size(120, 22)

$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Location = New-Object System.Drawing.Point(145, 347)
$urlBox.Size = New-Object System.Drawing.Size(445, 24)
$urlBox.ReadOnly = $true
$urlBox.Text = $info.McpUrl

$copyUrlButton = New-Object System.Windows.Forms.Button
$copyUrlButton.Text = "Copy URL"
$copyUrlButton.Location = New-Object System.Drawing.Point(610, 345)
$copyUrlButton.Size = New-Object System.Drawing.Size(120, 28)

$passwordLabel = New-Object System.Windows.Forms.Label
$passwordLabel.Text = "MCP password"
$passwordLabel.Location = New-Object System.Drawing.Point(18, 390)
$passwordLabel.Size = New-Object System.Drawing.Size(120, 22)

$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.Location = New-Object System.Drawing.Point(145, 387)
$passwordBox.Size = New-Object System.Drawing.Size(445, 24)
$passwordBox.ReadOnly = $true
$passwordBox.Text = $info.Password

$copyPasswordButton = New-Object System.Windows.Forms.Button
$copyPasswordButton.Text = "Copy Password"
$copyPasswordButton.Location = New-Object System.Drawing.Point(610, 385)
$copyPasswordButton.Size = New-Object System.Drawing.Size(120, 28)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "Start / Restart"
$startButton.Location = New-Object System.Drawing.Point(145, 465)
$startButton.Size = New-Object System.Drawing.Size(120, 34)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Location = New-Object System.Drawing.Point(278, 465)
$refreshButton.Size = New-Object System.Drawing.Size(95, 34)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Location = New-Object System.Drawing.Point(386, 465)
$stopButton.Size = New-Object System.Drawing.Size(95, 34)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(493, 465)
$closeButton.Size = New-Object System.Drawing.Size(95, 34)

$script:StartProcess = $null
$script:StopProcess = $null
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 2000

function Refresh-Fields {
    $latest = Get-ConnectionInfo
    $urlBox.Text = $latest.McpUrl
    $passwordBox.Text = $latest.Password
    if ($latest.Status) {
        $statusLabel.Text = "Status: $($latest.Status)"
    }
}

function Get-HostWorkspaceForRemote {
    param([string]$Preferred = "")

    $candidate = $Preferred.Trim()
    if (-not $candidate) {
        $latest = Get-ConnectionInfo
        $candidate = [string]$latest.Workspace
    }
    if (-not $candidate) {
        $candidate = $RepoPath
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        $candidate = $RepoPath
    }
    return $candidate
}

function Set-RemoteSummary {
    param($Remote)

    if ($Remote -and $Remote.Host) {
        $remoteSummaryLabel.Text = "Remote: $($Remote.User)@$($Remote.Host):$($Remote.Port) $($Remote.RemoteFolder)"
    }
    else {
        $remoteSummaryLabel.Text = "Remote: not saved"
    }
}

function Save-RemoteFromFields {
    param([switch]$AllowEmptyRemoteFolder)
    $remoteFolder = if ($AllowEmptyRemoteFolder) {
        Normalize-RemoteFolder -Path $remoteFolderBox.Text -AllowEmpty
    }
    else {
        Normalize-RemoteFolder -Path $remoteFolderBox.Text
    }
    $saved = Save-RemoteProfile `
        -Profile $remoteProfileBox.Text `
        -SshConnection $sshBox.Text `
        -Password $sshPasswordBox.Text `
        -RemoteFolder $remoteFolder
    $sshPasswordBox.Clear()
    Set-RemoteSummary -Remote $saved
    return $saved
}

function Set-ActiveTargetDisplay {
    param($Target)

    $mode = ""
    if ($Target -and $Target.PSObject.Properties["mode"]) {
        $mode = [string]$Target.mode
    }
    if ($mode -eq "remote") {
        $profile = [string]$Target.remote_profile
        $folder = [string]$Target.remote_folder
        if (-not $folder) {
            $folder = "(not selected)"
        }
        $activeTargetLabel.Text = "Remote target: $profile`:$folder"
        $useRemoteButton.BackColor = [System.Drawing.Color]::LightGreen
        $useLocalButton.BackColor = [System.Drawing.SystemColors]::Control
        $script:ActiveTargetMode = "remote"
        return
    }
    if ($mode -eq "unselected") {
        $activeTargetLabel.Text = "Target: not selected"
        $useLocalButton.BackColor = [System.Drawing.SystemColors]::Control
        $useRemoteButton.BackColor = [System.Drawing.SystemColors]::Control
        $script:ActiveTargetMode = ""
        return
    }

    $workspace = ""
    if ($Target -and $Target.PSObject.Properties["workspace_path"]) {
        $workspace = [string]$Target.workspace_path
    }
    if (-not $workspace) {
        $workspace = $workspaceBox.Text
    }
    $activeTargetLabel.Text = "Local target: $workspace"
    $useLocalButton.BackColor = [System.Drawing.Color]::LightGreen
    $useRemoteButton.BackColor = [System.Drawing.SystemColors]::Control
    $script:ActiveTargetMode = "local"
}

$pollTimer.Add_Tick({
    Refresh-Fields

    $startRunning = ($script:StartProcess -and -not $script:StartProcess.HasExited)
    $stopRunning = ($script:StopProcess -and -not $script:StopProcess.HasExited)

    $startButton.Enabled = -not $startRunning
    $stopButton.Enabled = -not $stopRunning
    $refreshButton.Enabled = $true

    if ($stopRunning) {
        $statusLabel.Text = "Status: stopping..."
        return
    }
    if ($startRunning) {
        if ($urlBox.Text) {
            $statusLabel.Text = "Status: starting in background; URL is ready"
        } else {
            $statusLabel.Text = "Status: starting in background..."
        }
        return
    }

    if ($script:StopProcess) {
        $exitCode = $script:StopProcess.ExitCode
        $script:StopProcess.Dispose()
        $script:StopProcess = $null
        Refresh-Fields
        if ($exitCode -eq 0) {
            $statusLabel.Text = "Status: stopped"
        } else {
            $statusLabel.Text = "Status: stop command exited with code $exitCode"
        }
        return
    }

    if ($script:StartProcess) {
        $exitCode = $script:StartProcess.ExitCode
        $script:StartProcess.Dispose()
        $script:StartProcess = $null
        Refresh-Fields
        if ($exitCode -ne 0) {
            $statusLabel.Text = "Status: start command exited with code $exitCode"
        } elseif ($urlBox.Text) {
            $statusLabel.Text = "Status: running"
        } else {
            $statusLabel.Text = "Status: starting; click Refresh in a few seconds"
        }
        return
    }

    if (-not $script:StartProcess -and -not $script:StopProcess) {
        $pollTimer.Stop()
    }
})

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select local host folder for this run"
    $dialog.ShowNewFolderButton = $true
    if ($workspaceBox.Text -and (Test-Path -LiteralPath $workspaceBox.Text -PathType Container)) {
        $dialog.SelectedPath = (Resolve-Path -LiteralPath $workspaceBox.Text).Path
    }
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $workspaceBox.Text = $dialog.SelectedPath
    }
})

$browseRemoteButton.Add_Click({
    try {
        $browseRemoteButton.Enabled = $false
        $statusLabel.Text = "Status: saving remote profile..."
        [System.Windows.Forms.Application]::DoEvents()

        $saved = Save-RemoteFromFields -AllowEmptyRemoteFolder
        $startPath = $remoteFolderBox.Text.Trim()
        if (-not $startPath) {
            $startPath = "/"
        }

        $statusLabel.Text = "Status: opening remote folder browser..."
        [System.Windows.Forms.Application]::DoEvents()

        $selectedPath = Show-RemoteFolderBrowser -Profile $saved.Profile -StartPath $startPath -Owner $form
        if ($selectedPath) {
            $remoteFolderBox.Text = $selectedPath
            $saved = Save-RemoteFromFields
            $saved.RemoteFolder = $selectedPath
            Set-RemoteSummary -Remote $saved
            $statusLabel.Text = "Status: remote folder selected"
        }
        else {
            $statusLabel.Text = "Status: remote folder selection canceled"
        }
    } catch {
        $statusLabel.Text = "Status: remote browse error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP Remote", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        $browseRemoteButton.Enabled = $true
    }
})

$useLocalButton.Add_Click({
    try {
        $workspace = $workspaceBox.Text.Trim()
        if (-not $workspace) {
            throw "Local folder is required."
        }
        if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
            throw "Local folder does not exist: $workspace"
        }
        $target = Write-ActiveTarget -Mode local -WorkspacePath $workspace
        Set-ActiveTargetDisplay -Target $target
        $statusLabel.Text = "Status: active target switched to local folder"
    } catch {
        $statusLabel.Text = "Status: local target error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$useRemoteButton.Add_Click({
    try {
        $saved = Save-RemoteFromFields
        $sshConnection = "ssh -p $($saved.Port) $($saved.User)@$($saved.Host)"
        $activeRemoteFolder = Normalize-RemoteFolder -Path $saved.RemoteFolder
        $hostWorkspace = Get-HostWorkspaceForRemote -Preferred $workspaceBox.Text
        $target = Write-ActiveTarget `
            -Mode remote `
            -WorkspacePath $hostWorkspace `
            -RemoteProfile $saved.Profile `
            -RemoteFolder $activeRemoteFolder `
            -SshConnection $sshConnection
        Set-ActiveTargetDisplay -Target $target
        $statusLabel.Text = "Status: active target switched to remote folder"
    } catch {
        $statusLabel.Text = "Status: remote target error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP Remote", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$copyUrlButton.Add_Click({
    Copy-Text -Text $urlBox.Text
    $statusLabel.Text = "Status: URL copied"
})

$copyPasswordButton.Add_Click({
    Copy-Text -Text $passwordBox.Text
    $statusLabel.Text = "Status: password copied"
})

$saveRemoteButton.Add_Click({
    try {
        $saved = Save-RemoteFromFields
        $statusLabel.Text = "Status: remote profile saved: $($saved.Profile)"
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "Saved remote profile '$($saved.Profile)' for $($saved.User)@$($saved.Host):$($saved.Port)`nRemote folder: $($saved.RemoteFolder)",
            "Coding MCP",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        $statusLabel.Text = "Status: remote save error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP Remote", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$testRemoteButton.Add_Click({
    try {
        $testRemoteButton.Enabled = $false
        $statusLabel.Text = "Status: testing remote..."
        [System.Windows.Forms.Application]::DoEvents()

        $saved = Save-RemoteFromFields
        $testFolder = $saved.RemoteFolder
        $testFolder = Normalize-RemoteFolder -Path $testFolder
        $remoteCommand = "cd $(Quote-RemoteShellString $testFolder); echo MCP_REMOTE_OK; whoami; hostname; pwd; ls -la"
        $result = Invoke-RemoteProfileCommand -Profile $saved.Profile -RemoteCommand $remoteCommand -TimeoutSeconds 35
        $statusLabel.Text = "Status: remote connected: $($saved.Profile)"
        $output = $result.Stdout.Trim()
        if ($result.Stderr.Trim()) {
            $output = ($output + "`n`nstderr:`n" + $result.Stderr.Trim()).Trim()
        }
        if ($output.Length -gt 3000) {
            $output = $output.Substring(0, 3000) + "`n... output truncated ..."
        }
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            $output,
            "Remote test: $($saved.Profile)",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        $statusLabel.Text = "Status: remote test failed"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP Remote", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        $testRemoteButton.Enabled = $true
    }
})

$refreshButton.Add_Click({
    Refresh-Fields
})

$closeButton.Add_Click({
    $form.Close()
})

$startButton.Add_Click({
    try {
        if ($script:StartProcess -and -not $script:StartProcess.HasExited) {
            $statusLabel.Text = "Status: already starting"
            return
        }
        if (-not $script:ActiveTargetMode) {
            throw "Choose Use Local Folder or Use Remote Folder before starting."
        }
        if ($script:ActiveTargetMode -eq "remote") {
            $workspace = Get-HostWorkspaceForRemote -Preferred $workspaceBox.Text
        }
        else {
            $workspace = $workspaceBox.Text.Trim()
            if (-not $workspace) {
                throw "Local folder is required."
            }
        }
        if (-not (Test-Path -LiteralPath $workspace -PathType Container)) {
            throw "Host workspace does not exist: $workspace"
        }

        $target = Read-ActiveTarget
        $targetMode = ""
        if ($target -and $target.PSObject.Properties["mode"]) {
            $targetMode = [string]$target.mode
        }
        if ($targetMode -ne $script:ActiveTargetMode) {
            throw "Active target was not saved correctly. Click Use Local Folder or Use Remote Folder again."
        }
        if ($script:ActiveTargetMode -eq "remote") {
            $target = Write-ActiveTarget `
                -Mode remote `
                -WorkspacePath $workspace `
                -RemoteProfile ([string]$target.remote_profile) `
                -RemoteFolder ([string]$target.remote_folder) `
                -SshConnection ([string]$target.ssh_connection)
            Set-ActiveTargetDisplay -Target $target
        }

        $statusLabel.Text = "Status: starting, please wait..."
        [System.Windows.Forms.Application]::DoEvents()

        $command = "& $(Quote-PsString $StartScript) -RepoPath $(Quote-PsString $RepoPath) -WorkspacePath $(Quote-PsString $workspace) -TunnelMode named -WaitSeconds 5"
        $script:StartProcess = Start-DetachedPowerShell -Command $command
        $startButton.Enabled = $false
        $statusLabel.Text = "Status: starting in background..."
        $pollTimer.Start()
    } catch {
        $statusLabel.Text = "Status: error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$stopButton.Add_Click({
    try {
        if ($script:StopProcess -and -not $script:StopProcess.HasExited) {
            $statusLabel.Text = "Status: already stopping"
            return
        }
        $command = "& $(Quote-PsString $StopScript) -RepoPath $(Quote-PsString $RepoPath)"
        $script:StopProcess = Start-DetachedPowerShell -Command $command
        $stopButton.Enabled = $false
        $statusLabel.Text = "Status: stopping..."
        $pollTimer.Start()
    } catch {
        $statusLabel.Text = "Status: error"
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, "Coding MCP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$form.Controls.AddRange(@(
    $workspaceLabel,
    $workspaceBox,
    $browseButton,
    $activeTargetLabel,
    $useLocalButton,
    $useRemoteButton,
    $remoteProfileLabel,
    $remoteProfileBox,
    $remoteSummaryLabel,
    $sshLabel,
    $sshBox,
    $saveRemoteButton,
    $sshPasswordLabel,
    $sshPasswordBox,
    $testRemoteButton,
    $remoteFolderLabel,
    $remoteFolderBox,
    $browseRemoteButton,
    $remoteFolderHintLabel,
    $statusLabel,
    $urlLabel,
    $urlBox,
    $copyUrlButton,
    $passwordLabel,
    $passwordBox,
    $copyPasswordButton,
    $startButton,
    $refreshButton,
    $stopButton,
    $closeButton
))

Set-ActiveTargetDisplay -Target $activeTarget

[void]$form.ShowDialog()
