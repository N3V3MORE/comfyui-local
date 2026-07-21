[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$DestinationRoot,
    [switch]$PrintPlan
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $SourceRoot = Join-Path $root 'workflows\apps' }
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Join-Path $root 'data\user\default\workflows\ComfyUI Local Studio'
}
$specs = (Read-Json (Join-Path $root 'config\workflow-specs.json')).apps

if ($PrintPlan) {
    foreach ($spec in $specs) { Write-Output "$($spec.id)`t$($spec.output.Replace('/', '\'))" }
    exit 0
}

foreach ($spec in $specs) {
    $relativePath = $spec.output.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $source = Join-Path $SourceRoot $relativePath
    $destination = Join-Path $DestinationRoot $relativePath
    Assert-Condition (Test-Path -LiteralPath $source) "$($spec.id) compiled workflow is missing"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

Write-Output "Installed $($specs.Count) App Mode workflows"
