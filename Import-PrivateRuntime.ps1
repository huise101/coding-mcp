param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [string]$DestinationRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $DestinationRoot) {
    $DestinationRoot = Split-Path -Parent $PSCommandPath
}
$DestinationRoot = (Resolve-Path -LiteralPath $DestinationRoot).Path

if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw "Private runtime zip not found: $ZipPath"
}

$repoRuntime = Join-Path $DestinationRoot "coding-tools-mcp\.runtime"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("coding-mcp-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempRoot -Force
    $runtime = Get-ChildItem -LiteralPath $tempRoot -Recurse -Directory -Force |
        Where-Object { $_.FullName -match '\\coding-tools-mcp\\\.runtime$' } |
        Select-Object -First 1
    if (-not $runtime) {
        $runtime = Get-ChildItem -LiteralPath $tempRoot -Recurse -Directory -Force |
            Where-Object { $_.Name -eq ".runtime" } |
            Select-Object -First 1
    }
    if (-not $runtime) {
        throw "No coding-tools-mcp\.runtime folder found inside the private zip."
    }

    if (Test-Path -LiteralPath $repoRuntime) {
        $backup = Join-Path $DestinationRoot ("coding-tools-mcp\.runtime.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        Move-Item -LiteralPath $repoRuntime -Destination $backup
        Write-Host "Existing runtime backed up:"
        Write-Host $backup
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $repoRuntime) | Out-Null
    Copy-Item -LiteralPath $runtime.FullName -Destination $repoRuntime -Recurse -Force
    Write-Host "Private runtime imported:"
    Write-Host $repoRuntime
    Write-Host "Next: double-click Start-CodingMCP.vbs"
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
