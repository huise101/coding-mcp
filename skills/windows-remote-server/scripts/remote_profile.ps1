Set-StrictMode -Version Latest

function Assert-RemoteProfileName {
    param([Parameter(Mandatory = $true)][string]$Profile)

    if ($Profile -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "Invalid profile name '$Profile'. Use letters, digits, dot, underscore, or hyphen only."
    }
}

function Get-RemoteStoreRoot {
    param([string]$Root = ".codex-remote")

    if ([System.IO.Path]::IsPathRooted($Root)) {
        return $Root
    }

    return (Join-Path (Get-Location) $Root)
}

function Import-RemoteEnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Profile env file not found: $Path"
    }

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $index = $line.IndexOf("=")
        if ($index -lt 1) {
            continue
        }

        $key = $line.Substring(0, $index).Trim()
        $value = $line.Substring($index + 1).Trim()

        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment key in $Path`: $key"
        }

        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        Set-Item -Path "Env:$key" -Value $value
    }
}

function Set-RemotePasswordFromCredentialXml {
    param([Parameter(Mandatory = $true)][string]$CredentialXml)

    if (-not (Test-Path -LiteralPath $CredentialXml)) {
        throw "Credential XML not found: $CredentialXml"
    }

    $credential = Import-Clixml -LiteralPath $CredentialXml
    if (-not $env:REMOTE_USER) {
        $env:REMOTE_USER = $credential.UserName
    }

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
    try {
        $env:REMOTE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Use-RemoteProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Profile,
        [string]$Root = ".codex-remote"
    )

    Assert-RemoteProfileName -Profile $Profile
    $storeRoot = Get-RemoteStoreRoot -Root $Root
    $profilePath = Join-Path (Join-Path $storeRoot "profiles") "$Profile.env"

    Import-RemoteEnvFile -Path $profilePath

    if ($env:REMOTE_CREDENTIAL_XML) {
        $credentialPath = $env:REMOTE_CREDENTIAL_XML
        if (-not [System.IO.Path]::IsPathRooted($credentialPath)) {
            $credentialPath = Join-Path $storeRoot $credentialPath
        }
        Set-RemotePasswordFromCredentialXml -CredentialXml $credentialPath
    }

    foreach ($required in @("REMOTE_HOST", "REMOTE_PORT", "REMOTE_USER")) {
        if (-not (Get-Item -Path "Env:$required" -ErrorAction SilentlyContinue)) {
            throw "Profile '$Profile' is missing $required."
        }
    }
}
