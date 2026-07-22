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
$defaultDestinationRoot = Join-Path $root 'data\user\default\workflows\ComfyUI Local Studio'
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) { $DestinationRoot = $defaultDestinationRoot }
$destinationIsDefault = [string]::Equals(
    [IO.Path]::GetFullPath($DestinationRoot),
    [IO.Path]::GetFullPath($defaultDestinationRoot),
    [StringComparison]::OrdinalIgnoreCase
)
$specs = (Read-Json (Join-Path $root 'config\workflow-specs.json')).apps
$expectedRelativePaths = @()

if ($PrintPlan) {
    foreach ($spec in $specs) { Write-Output "$($spec.id)`t$($spec.output.Replace('/', '\'))" }
    exit 0
}

foreach ($spec in $specs) {
    $relativePath = Assert-SafeRelativePath -Path $spec.output -Label "Workflow $($spec.id) output"
    $expectedRelativePaths += $relativePath
    $source = Resolve-ManagedPath -Root $SourceRoot -RelativePath $relativePath -Label "Workflow $($spec.id) source"
    $destination = Resolve-ManagedPath -Root $DestinationRoot -RelativePath $relativePath -Label "Workflow $($spec.id) destination"
    Assert-Condition (Test-Path -LiteralPath $source) "$($spec.id) compiled workflow is missing"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

if ($destinationIsDefault -and (Test-Path -LiteralPath $DestinationRoot)) {
    $destinationPath = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\', '/')
    foreach ($installed in Get-ChildItem -LiteralPath $DestinationRoot -Recurse -Filter '*.app.json') {
        $relativePath = $installed.FullName.Substring($destinationPath.Length).TrimStart('\', '/')
        if ($relativePath -notin $expectedRelativePaths) {
            Remove-Item -LiteralPath $installed.FullName -Force
        }
    }
}
elseif (-not $destinationIsDefault) {
    Write-Output 'Skipped stale app reconciliation for a custom destination root'
}

Write-Output "Installed $($specs.Count) App Mode workflows"
