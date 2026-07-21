[CmdletBinding()]
param(
    [switch]$StaticOnly,
    [switch]$RequireModels,
    [switch]$SkipArtifactHashes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'download-models.ps1') -LibraryOnly

$root = Get-ProjectRoot
$version = Read-Json (Join-Path $root 'comfyui-version.json')
$manifest = Read-Json (Join-Path $root 'model-manifest.json')
$python = Join-Path $root '.venv\Scripts\python.exe'
$comfyPath = Join-Path $root 'ComfyUI'
$modelsRoot = Join-Path $root 'models'
$workflowRoot = Join-Path $root 'workflows\ui'

Assert-Condition (-not $SkipArtifactHashes -or $StaticOnly) '-SkipArtifactHashes requires -StaticOnly'

Assert-Condition (Test-Path -LiteralPath $python) 'Python environment is missing'
Assert-Condition (Test-Path -LiteralPath (Join-Path $comfyPath '.git')) 'ComfyUI checkout is missing'

$commit = (& git -C $comfyPath rev-parse HEAD).Trim()
Assert-Condition ($LASTEXITCODE -eq 0) 'Could not inspect the ComfyUI commit'
Assert-Condition ($commit -eq $version.commit) "Unexpected ComfyUI commit: $commit"

$probeCode = @'
import json
import torch
print(json.dumps({
    "torch": torch.__version__,
    "cuda": torch.cuda.is_available(),
    "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
    "vramBytes": torch.cuda.get_device_properties(0).total_memory if torch.cuda.is_available() else 0,
}))
'@
$probeOutput = $probeCode | & $python -
Assert-Condition ($LASTEXITCODE -eq 0) 'PyTorch probe failed'
$probe = $probeOutput | ConvertFrom-Json
Assert-Condition ($probe.torch -eq $version.torch) "Unexpected Torch version: $($probe.torch)"
Assert-Condition $probe.cuda 'CUDA is unavailable'
Assert-Condition ($probe.gpu -eq 'NVIDIA GeForce RTX 5060 Laptop GPU') "Unexpected GPU: $($probe.gpu)"
Assert-Condition ([long]$probe.vramBytes -gt 7.5GB) 'Less than 7.5 GiB VRAM is visible to PyTorch'

$validArtifacts = $missingArtifacts = $invalidArtifacts = 0
if (-not $SkipArtifactHashes) {
    foreach ($artifact in $manifest.artifacts) {
        $path = Join-Path $modelsRoot $artifact.target.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path)) {
            $missingArtifacts++
        }
        elseif (Test-Artifact -Path $path -Bytes $artifact.bytes -Sha256 $artifact.sha256) {
            $validArtifacts++
        }
        else {
            $invalidArtifacts++
        }
    }
}

$workflowFiles = @(Get-ChildItem -LiteralPath $workflowRoot -Filter '*.json')
$validWorkflows = 0
foreach ($workflowFile in $workflowFiles) {
    try {
        $workflow = Get-Content -LiteralPath $workflowFile.FullName -Raw | ConvertFrom-Json
        if ($workflow.version -eq 0.4) { $validWorkflows++ }
    }
    catch {
        throw "Invalid workflow JSON: $($workflowFile.Name)"
    }
}
Assert-Condition ($validWorkflows -eq 4) "Expected four valid UI workflows; found $validWorkflows"

$httpHealthy = $false
$systemStats = $null
if (-not $StaticOnly) {
    $systemStats = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/system_stats' -TimeoutSec 10
    $httpHealthy = $null -ne $systemStats
    Assert-Condition $httpHealthy 'ComfyUI health endpoint did not respond'
}

$result = [ordered]@{
    checkedAt = (Get-Date).ToString('o')
    comfyCommit = $commit
    torch = $probe.torch
    cudaAvailable = [bool]$probe.cuda
    gpu = $probe.gpu
    vramBytes = [long]$probe.vramBytes
    artifacts = [ordered]@{
        records = $manifest.artifacts.Count
        hashesSkipped = [bool]$SkipArtifactHashes
        valid = $validArtifacts
        missing = $missingArtifacts
        invalid = $invalidArtifacts
    }
    uiWorkflows = $validWorkflows
    httpHealthy = $httpHealthy
}

$resultsRoot = Join-Path $root 'results'
New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
[IO.File]::WriteAllText(
    (Join-Path $resultsRoot 'verification.json'),
    ($result | ConvertTo-Json -Depth 10) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

Write-Output "ComfyUI commit: $commit"
Write-Output "Torch: $($probe.torch)"
Write-Output "CUDA available: $($probe.cuda)"
Write-Output "GPU: $($probe.gpu)"
if ($SkipArtifactHashes) {
    Write-Output "Artifact records: $($manifest.artifacts.Count); hash checks skipped"
}
else {
    Write-Output "Artifacts: $validArtifacts valid, $missingArtifacts missing, $invalidArtifacts invalid"
}
Write-Output "UI workflows: $validWorkflows valid"
if (-not $StaticOnly) { Write-Output 'HTTP: healthy at http://127.0.0.1:8188' }

if (-not $SkipArtifactHashes) {
    Assert-Condition ($invalidArtifacts -eq 0) "$invalidArtifacts model artifacts are invalid"
    if ($RequireModels -or -not $StaticOnly) {
        Assert-Condition ($missingArtifacts -eq 0) "$missingArtifacts model artifacts are missing"
    }
}
