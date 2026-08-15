$ErrorActionPreference = "Stop"

$LauncherDir = Split-Path -Parent $PSCommandPath
$BasePath = Split-Path -Parent $LauncherDir
$RepoPath = Join-Path $BasePath "coding-tools-mcp"
$StopScript = Join-Path $BasePath "skills\coding-tools-mcp-remote\scripts\Stop-CodingToolsMcpRemote.ps1"

function Quote-PsString {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-HiddenPowerShell {
    param(
        [string]$Command,
        [int]$TimeoutSeconds = 60
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
        throw "The stop command timed out after $TimeoutSeconds seconds."
    }
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.Result
        Stderr = $stderrTask.Result
    }
}

Add-Type -AssemblyName System.Windows.Forms

try {
    $command = "& $(Quote-PsString $StopScript) -RepoPath $(Quote-PsString $RepoPath)"
    $result = Invoke-HiddenPowerShell -Command $command -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) {
        $detail = ($result.Stderr + "`r`n" + $result.Stdout).Trim()
        if ($detail.Length -gt 1500) {
            $detail = $detail.Substring(0, 1500)
        }
        throw "Stop failed.`r`n$detail"
    }
    [System.Windows.Forms.MessageBox]::Show("Coding MCP has been stopped.", "Coding MCP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Coding MCP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
