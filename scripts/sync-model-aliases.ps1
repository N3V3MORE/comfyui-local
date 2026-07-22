[CmdletBinding()]
param([switch]$LibraryOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

function New-ModelAlias {
    param(
        [Parameter(Mandatory)]$Alias,
        [Parameter(Mandatory)][string]$ModelsRoot
    )

    $source = Resolve-ManagedPath -Root $ModelsRoot -RelativePath $Alias.source -Label 'Alias source'
    $target = Resolve-ManagedPath -Root $ModelsRoot -RelativePath $Alias.target -Label 'Alias target'
    Assert-Condition (Test-Path -LiteralPath $source -PathType Leaf) "Alias source is missing: $source"

    if (Test-Path -LiteralPath $target) {
        Assert-Condition ((Get-FileId $source) -eq (Get-FileId $target)) "Alias target is not linked to its source: $target"
        return 'existing'
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    New-Item -ItemType HardLink -Path $target -Target $source | Out-Null
    Assert-Condition ((Get-FileId $source) -eq (Get-FileId $target)) "Hardlink creation failed: $target"
    return 'created'
}

if ($LibraryOnly) { return }

$root = Get-ProjectRoot
$manifest = Read-Json (Join-Path $root 'config\model-aliases.json')
$modelsRoot = Join-Path $root 'models'
foreach ($alias in $manifest.aliases) {
    $result = New-ModelAlias -Alias $alias -ModelsRoot $modelsRoot
    Write-Output "$($result.ToUpperInvariant()) $($alias.target)"
}
