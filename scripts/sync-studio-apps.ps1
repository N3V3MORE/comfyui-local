[CmdletBinding()]
param([switch]$PrintPlan)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PrintPlan) {
    & (Join-Path $PSScriptRoot 'install-workflows.ps1') -PrintPlan
    exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot 'compile.ps1')
& (Join-Path $PSScriptRoot 'copy-bundled-inputs.ps1')
& (Join-Path $PSScriptRoot 'install-workflows.ps1')
