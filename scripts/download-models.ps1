[CmdletBinding()]
param(
    [string[]]$Id,
    [switch]$VerifyOnly,
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

function Test-Artifact {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$Bytes,
        [Parameter(Mandatory)][string]$Sha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -ne $Bytes) { return $false }
    return (Get-FileSha256 -Path $Path) -eq $Sha256.ToLowerInvariant()
}

function Install-Artifact {
    param(
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)][string]$ModelsRoot
    )

    $relativeTarget = $Artifact.target.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $destination = Join-Path $ModelsRoot $relativeTarget
    $partial = "$destination.partial"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null

    if (Test-Artifact -Path $destination -Bytes $Artifact.bytes -Sha256 $Artifact.sha256) {
        return 'skipped'
    }

    & curl.exe --silent --show-error --location --fail --retry 5 --retry-delay 5 --continue-at - --output $partial $Artifact.url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $($Artifact.id)" }

    if (-not (Test-Artifact -Path $partial -Bytes $Artifact.bytes -Sha256 $Artifact.sha256)) {
        throw "Integrity check failed: $($Artifact.id)"
    }

    Move-Item -LiteralPath $partial -Destination $destination -Force
    return 'installed'
}

if ($LibraryOnly) { return }

$root = Get-ProjectRoot
$modelsRoot = Join-Path $root 'models'
$manifest = Read-Json (Join-Path $root 'model-manifest.json')
$artifacts = @($manifest.artifacts)

if ($Id.Count -gt 0) {
    $unknown = @($Id | Where-Object { $_ -notin $artifacts.id })
    if ($unknown.Count -gt 0) { throw "Unknown artifact id: $($unknown -join ', ')" }
    $artifacts = @($artifacts | Where-Object { $_.id -in $Id })
}

$invalidCount = 0
if ($VerifyOnly) {
    foreach ($artifact in $artifacts) {
        $path = Join-Path $modelsRoot $artifact.target.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Artifact -Path $path -Bytes $artifact.bytes -Sha256 $artifact.sha256) {
            Write-Output "VALID $($artifact.id)"
        }
        else {
            $invalidCount++
            $state = if (Test-Path -LiteralPath $path) { 'INVALID' } else { 'MISSING' }
            Write-Output "$state $($artifact.id)"
        }
    }
    if ($invalidCount -gt 0) { throw "$invalidCount artifact(s) are missing or invalid" }
    return
}

$requiresDownload = $false
foreach ($artifact in $artifacts) {
    $path = Join-Path $modelsRoot $artifact.target.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Artifact -Path $path -Bytes $artifact.bytes -Sha256 $artifact.sha256)) {
        $requiresDownload = $true
        break
    }
}

if ($requiresDownload) {
    $driveName = [IO.Path]::GetPathRoot($root).TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName
    Assert-Condition ($drive.Free -ge [long]$manifest.requiredFreeBytes) 'Less than 70 GiB of free disk space remains'
}

foreach ($artifact in $artifacts) {
    Write-Output "Checking $($artifact.id)"
    $result = Install-Artifact -Artifact $artifact -ModelsRoot $modelsRoot
    Write-Output "$($result.ToUpperInvariant()) $($artifact.id)"
}
