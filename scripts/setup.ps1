[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ValidateOnly,
    [switch]$PrintExtraModelPaths,
    [switch]$PrintSyncCommand,
    [switch]$PrintVenvAction
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
$version = Read-Json (Join-Path $root 'comfyui-version.json')
$manifest = Read-Json (Join-Path $root 'model-manifest.json')
$comfyPath = Join-Path $root 'ComfyUI'
$venvPath = Join-Path $root '.venv'
$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
$lockPath = Join-Path $root 'requirements.lock.txt'
$syncArguments = @(
    'pip', 'sync',
    '--python', $pythonPath,
    '--extra-index-url', $version.torchIndex,
    '--index-strategy', 'unsafe-best-match',
    $lockPath
)

function Invoke-Native {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Get-ExtraModelPathsYaml {
    $modelPath = (Join-Path $root 'models').Replace('\', '/')
    return @"
comfyui_local:
  base_path: $modelPath
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  text_encoders: text_encoders
  vae: vae
"@.Trim()
}

function Test-Prerequisites {
    foreach ($commandName in @('git', 'uv', 'curl.exe', 'nvidia-smi')) {
        Assert-Condition (Test-Command $commandName) "$commandName is required"
        Write-Output "${commandName}: available"
    }

    $pythonOutput = & uv python find $version.python 2>&1
    $pythonExitCode = $LASTEXITCODE
    $python = ($pythonOutput | Select-Object -Last 1).ToString().Trim()
    Assert-Condition ($pythonExitCode -eq 0 -and (Test-Path -LiteralPath $python)) 'Python 3.13 is not available through uv'
    Write-Output "Python 3.13: $python"

    $gpuOutput = & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1
    $gpuExitCode = $LASTEXITCODE
    $gpu = ($gpuOutput | Select-Object -First 1).ToString().Trim()
    Assert-Condition ($gpuExitCode -eq 0) 'nvidia-smi could not query the GPU'
    Assert-Condition ($gpu -match 'NVIDIA GeForce RTX 5060 Laptop GPU') "Unexpected GPU: $gpu"
    Write-Output "NVIDIA GeForce RTX 5060 Laptop GPU: $gpu"

    $driveName = [IO.Path]::GetPathRoot($root).TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName
    Assert-Condition ($drive.Free -ge [long]$manifest.requiredFreeBytes) 'Less than 70 GiB of free disk space remains'
    Write-Output ('free disk space: {0:N1} GiB' -f ($drive.Free / 1GB))
}

if ($PrintExtraModelPaths) {
    Write-Output (Get-ExtraModelPathsYaml)
    exit 0
}

if ($PrintSyncCommand) {
    Write-Output ((@('uv') + $syncArguments) -join ' ')
    exit 0
}

if ($PrintVenvAction) {
    if (Test-Path -LiteralPath $pythonPath) { Write-Output 'reuse' } else { Write-Output 'create' }
    exit 0
}

Test-Prerequisites
if ($ValidateOnly) { exit 0 }

if (-not (Test-Path -LiteralPath $comfyPath)) {
    if ($PSCmdlet.ShouldProcess($comfyPath, 'Clone official ComfyUI')) {
        Invoke-Native git @('clone', '--filter=blob:none', $version.repository, $comfyPath)
    }
}

Assert-Condition (Test-Path -LiteralPath (Join-Path $comfyPath '.git')) 'ComfyUI exists but is not a Git checkout'
$remote = (& git -C $comfyPath remote get-url origin).Trim()
Assert-Condition ($remote -eq $version.repository) "Unexpected ComfyUI origin: $remote"

if ($PSCmdlet.ShouldProcess($comfyPath, "Checkout $($version.commit)")) {
    Invoke-Native git @('-C', $comfyPath, 'fetch', 'origin', $version.commit, '--depth', '1')
    Invoke-Native git @('-C', $comfyPath, 'checkout', '--detach', $version.commit)
}

Assert-Condition (Test-Path -LiteralPath $lockPath) 'requirements.lock.txt has not been generated'
if ($PSCmdlet.ShouldProcess($venvPath, 'Create and synchronize Python environment')) {
    if (-not (Test-Path -LiteralPath $pythonPath)) {
        Invoke-Native uv @('venv', '--python', $version.python, $venvPath)
    }
    else {
        Write-Output "Reusing Python environment at $venvPath"
    }
    Invoke-Native uv $syncArguments
}

foreach ($relativePath in @('checkpoints\realistic', 'checkpoints\anime', 'diffusion_models', 'text_encoders', 'vae')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root "models\$relativePath") | Out-Null
}

$extraPathsFile = Join-Path $comfyPath 'extra_model_paths.yaml'
Set-Content -LiteralPath $extraPathsFile -Value (Get-ExtraModelPathsYaml) -Encoding utf8
Write-Output "ComfyUI runtime ready at $comfyPath"
Write-Output "Python environment ready at $venvPath"
