[CmdletBinding()]
param(
    [switch]$LowVram,
    [switch]$CoreOnly,
    [switch]$PrintCommand,
    [switch]$PrintEnvironment
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
$python = Join-Path $root '.venv\Scripts\python.exe'
$main = Join-Path $root 'ComfyUI\main.py'
$models = Join-Path $root 'models'
$user = Join-Path $root 'data\user'
$inputDirectory = Join-Path $root 'data\input'
$tempDirectory = Join-Path $root 'data\temp'
$outputDirectory = Join-Path $root 'results\images'
$resolutionConfig = Join-Path $root 'config\resolutions.json'
$arguments = @(
    $main,
    '--listen', '127.0.0.1',
    '--port', '8188',
    '--preview-method', 'auto',
    '--models-directory', $models,
    '--user-directory', $user,
    '--input-directory', $inputDirectory,
    '--temp-directory', $tempDirectory,
    '--output-directory', $outputDirectory,
    '--enable-manager'
)
if ($LowVram) { $arguments += '--lowvram' }
if ($CoreOnly) { $arguments += '--disable-all-custom-nodes' }

if ($PrintCommand) {
    Write-Output ((@($python) + $arguments) -join ' ')
    exit 0
}
if ($PrintEnvironment) {
    Write-Output "COMFYUI_LOCAL_CONFIG=$resolutionConfig"
    exit 0
}

Assert-Condition (Test-Path -LiteralPath $python) 'Run scripts/setup.ps1 before starting ComfyUI'
Assert-Condition (Test-Path -LiteralPath $main) 'Pinned ComfyUI checkout is missing'

foreach ($path in @($models, $user, $inputDirectory, $tempDirectory, $outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}
$env:AUX_ANNOTATOR_CKPTS_PATH = Join-Path $models 'controlnet_aux'
$env:COMFYUI_LOCAL_CONFIG = $resolutionConfig

try {
    $existing = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/system_stats' -TimeoutSec 2
    if ($null -ne $existing) {
        Write-Output 'ComfyUI is already healthy at http://127.0.0.1:8188'
        exit 0
    }
}
catch {
    # No healthy server is expected before launch.
}

$listener = Get-NetTCPConnection -LocalPort 8188 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $listener) {
    throw "Port 8188 is already owned by PID $($listener.OwningProcess)"
}

Write-Output 'Starting ComfyUI at http://127.0.0.1:8188'
Push-Location (Join-Path $root 'ComfyUI')
try {
    & $python @arguments
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
