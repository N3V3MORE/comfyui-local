[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$verifyScript = Join-Path $projectRoot 'scripts\verify.ps1'

& $verifyScript -RequireExtensions
if ($LASTEXITCODE -ne 0) {
    throw "Live verification failed with exit code $LASTEXITCODE"
}
