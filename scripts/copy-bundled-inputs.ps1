[CmdletBinding()]
param([string]$DestinationRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) { $DestinationRoot = Join-Path $root 'data\input' }
$source = Join-Path $root '.venv\Lib\site-packages\comfyui_workflow_templates_media_image\templates\image_z_image_turbo_fun_union_controlnet-1.webp'
$destination = Join-Path $DestinationRoot 'studio-reference.webp'

Assert-Condition (Test-Path -LiteralPath $source) 'Pinned studio reference image is missing'
New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Output "Installed bundled input at $destination"
