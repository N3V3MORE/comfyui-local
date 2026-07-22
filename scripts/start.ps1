[CmdletBinding()]
param(
    [switch]$LowVram,
    [switch]$CoreOnly,
    [switch]$EnableManager,
    [switch]$PrintCommand,
    [switch]$PrintEnvironment
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
$python = Resolve-ManagedPath -Root $root -RelativePath '.venv\Scripts\python.exe' -Label 'Python environment'
$main = Resolve-ManagedPath -Root $root -RelativePath 'ComfyUI\main.py' -Label 'ComfyUI entrypoint'
$models = Resolve-ManagedPath -Root $root -RelativePath 'models' -Label 'Models directory'
$user = Resolve-ManagedPath -Root $root -RelativePath 'data\user' -Label 'User data directory'
$inputDirectory = Resolve-ManagedPath -Root $root -RelativePath 'data\input' -Label 'Input directory'
$tempDirectory = Resolve-ManagedPath -Root $root -RelativePath 'data\temp' -Label 'Temporary directory'
$outputDirectory = Resolve-ManagedPath -Root $root -RelativePath 'results\images' -Label 'Output directory'
$resolutionConfig = Resolve-ManagedPath -Root $root -RelativePath 'config\resolutions.json' -Label 'Resolution configuration'
$arguments = @(
    $main,
    '--listen', '127.0.0.1',
    '--port', '8188',
    '--preview-method', 'auto',
    '--models-directory', $models,
    '--user-directory', $user,
    '--input-directory', $inputDirectory,
    '--temp-directory', $tempDirectory,
    '--output-directory', $outputDirectory
)
if ($LowVram) { $arguments += '--lowvram' }
if ($CoreOnly) { $arguments += '--disable-all-custom-nodes' }
if ($EnableManager) { $arguments += '--enable-manager' }

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
$env:AUX_ANNOTATOR_CKPTS_PATH = Resolve-ManagedPath -Root $models -RelativePath 'controlnet_aux' -Label 'ControlNet auxiliary checkpoint directory'
$env:COMFYUI_LOCAL_CONFIG = $resolutionConfig

$listener = Get-NetTCPConnection -LocalPort 8188 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $listener) {
    try {
        $existing = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/system_stats' -TimeoutSec 2
        $studioNode = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/object_info/StudioResolutionPreset' -TimeoutSec 2
    }
    catch {
        throw "Port 8188 is already owned by PID $($listener.OwningProcess) and is not a healthy ComfyUI Local Studio server"
    }
    Assert-Condition ($null -ne $existing -and $null -ne $studioNode) 'Port 8188 is occupied by a ComfyUI server that does not expose ComfyUI Local Studio'

    $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    $commandLine = [string]$process.CommandLine
    foreach ($expectedPath in @($python, $main, $models, $user, $inputDirectory, $tempDirectory, $outputDirectory)) {
        $normalizedPath = [IO.Path]::GetFullPath($expectedPath)
        Assert-Condition (
            $commandLine.IndexOf($normalizedPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
        ) "Port 8188 is occupied by a Studio server that does not belong to this checkout"
    }
    Write-Output 'ComfyUI Local Studio is already healthy at http://127.0.0.1:8188'
    exit 0
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
