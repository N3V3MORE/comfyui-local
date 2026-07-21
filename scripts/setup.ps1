[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ValidateOnly,
    [switch]$PrintExtraModelPaths,
    [switch]$PrintSyncCommand,
    [switch]$PrintVenvAction,
    [switch]$PrintExtensionPlan,
    [switch]$PrintExtensionHookPolicy,
    [switch]$RepairExtensions
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
$version = Read-Json (Join-Path $root 'comfyui-version.json')
$manifest = Read-Json (Join-Path $root 'config\artifacts.json')
$extensionsManifest = Read-Json (Join-Path $root 'extensions-manifest.json')
$comfyPath = Join-Path $root 'ComfyUI'
$venvPath = Join-Path $root '.venv'
$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
$lockPath = Join-Path $root 'requirements.lock.txt'
$extensionDownloadMarker = Join-Path $comfyPath 'custom_nodes\skip_download_model'
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

function Invoke-ExtensionInstall {
    param([Parameter(Mandatory)]$Extension)

    $customNodesPath = Join-Path $comfyPath 'custom_nodes'
    $extensionPath = Join-Path $customNodesPath $Extension.name
    $wasInstalled = $false
    New-Item -ItemType Directory -Force -Path $customNodesPath | Out-Null

    if (-not (Test-Path -LiteralPath $extensionPath)) {
        if ($PSCmdlet.ShouldProcess($extensionPath, "Clone $($Extension.id)")) {
            Invoke-Native git @('clone', '--filter=blob:none', $Extension.repository, $extensionPath)
            $wasInstalled = $true
        }
    }

    Assert-Condition (Test-Path -LiteralPath (Join-Path $extensionPath '.git')) "$($Extension.id) is not a Git checkout"
    $origin = (& git -C $extensionPath remote get-url origin).Trim()
    Assert-Condition ($origin -eq $Extension.repository) "Unexpected $($Extension.id) origin: $origin"

    $dirty = (& git -C $extensionPath status --porcelain) -join ''
    if (-not [string]::IsNullOrWhiteSpace($dirty)) {
        Assert-Condition $RepairExtensions "$($Extension.id) has local changes; rerun with -RepairExtensions to restore its pin"
        if ($PSCmdlet.ShouldProcess($extensionPath, "Discard local changes in $($Extension.id)")) {
            Invoke-Native git @('-C', $extensionPath, 'reset', '--hard', 'HEAD')
            Invoke-Native git @('-C', $extensionPath, 'clean', '-fd')
        }
    }

    $currentCommit = (& git -C $extensionPath rev-parse HEAD).Trim()
    if ($currentCommit -ne $Extension.commit) {
        if ($PSCmdlet.ShouldProcess($extensionPath, "Checkout $($Extension.commit)")) {
            Invoke-Native git @('-C', $extensionPath, 'fetch', 'origin', $Extension.commit, '--depth', '1')
            Invoke-Native git @('-C', $extensionPath, 'checkout', '--detach', $Extension.commit)
            $wasInstalled = $true
        }
    }

    $actualCommit = (& git -C $extensionPath rev-parse HEAD).Trim()
    Assert-Condition ($actualCommit -eq $Extension.commit) "Unexpected $($Extension.id) commit: $actualCommit"

    if ($wasInstalled -and -not [string]::IsNullOrWhiteSpace($Extension.installHook)) {
        $hook = Join-Path $extensionPath $Extension.installHook
        Assert-Condition (Test-Path -LiteralPath $hook) "$($Extension.id) install hook is missing"
        if ($PSCmdlet.ShouldProcess($hook, "Run $($Extension.id) install hook")) {
            Invoke-Native $pythonPath @($hook)
        }
    }
}

function Install-LocalStudioNode {
    $source = Join-Path $root 'custom_nodes\comfyui_local_studio'
    $destination = Join-Path $comfyPath 'custom_nodes\comfyui_local_studio'
    Assert-Condition (Test-Path -LiteralPath (Join-Path $source '__init__.py')) 'Tracked studio node is missing'

    if (Test-Path -LiteralPath $destination) {
        $item = Get-Item -LiteralPath $destination -Force
        Assert-Condition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Studio node destination exists but is not a link'
        return
    }

    if ($PSCmdlet.ShouldProcess($destination, 'Link tracked studio node into ComfyUI')) {
        New-Item -ItemType Junction -Path $destination -Target $source | Out-Null
    }
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

if ($PrintExtensionPlan) {
    foreach ($extension in $extensionsManifest.extensions) {
        Write-Output "$($extension.id)@$($extension.commit)"
    }
    Write-Output 'comfyui-local-studio@tracked'
    exit 0
}

if ($PrintExtensionHookPolicy) {
    Write-Output "COMFYUI_PATH=$comfyPath"
    Write-Output "COMFYUI_MODEL_PATH=$(Join-Path $root 'models')"
    Write-Output "SKIP_DOWNLOAD_MARKER=$extensionDownloadMarker"
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

# Impact Pack and its subpack honor this marker. All model downloads belong in
# the reviewed manifests instead of being hidden side effects of install hooks.
$customNodesPath = Split-Path -Parent $extensionDownloadMarker
New-Item -ItemType Directory -Force -Path $customNodesPath | Out-Null
New-Item -ItemType File -Force -Path $extensionDownloadMarker | Out-Null
$env:COMFYUI_PATH = $comfyPath
$env:COMFYUI_MODEL_PATH = Join-Path $root 'models'

foreach ($extension in $extensionsManifest.extensions) {
    Invoke-ExtensionInstall -Extension $extension
}
Install-LocalStudioNode

# Install hooks may inspect or modify the environment. The committed lock wins.
if ($PSCmdlet.ShouldProcess($venvPath, 'Re-synchronize pinned packages after extension hooks')) {
    Invoke-Native uv $syncArguments
}

foreach ($relativePath in @(
    'checkpoints\realistic',
    'checkpoints\anime',
    'diffusion_models',
    'text_encoders',
    'vae',
    'controlnet',
    'model_patches',
    'clip_vision',
    'ipadapter',
    'controlnet_aux',
    'upscale_models',
    'ultralytics\bbox',
    'loras\sdxl',
    'loras\z-image',
    'loras\flux2'
)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root "models\$relativePath") | Out-Null
}

foreach ($relativePath in @('data\user', 'data\input', 'data\temp', 'results\images')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $relativePath) | Out-Null
}

$extraPathsFile = Join-Path $comfyPath 'extra_model_paths.yaml'
Set-Content -LiteralPath $extraPathsFile -Value (Get-ExtraModelPathsYaml) -Encoding utf8
& (Join-Path $PSScriptRoot 'compile.ps1')
& (Join-Path $PSScriptRoot 'copy-bundled-inputs.ps1')
& (Join-Path $PSScriptRoot 'install-workflows.ps1')
Write-Output "ComfyUI runtime ready at $comfyPath"
Write-Output "Python environment ready at $venvPath"
