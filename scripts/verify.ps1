[CmdletBinding()]
param(
    [switch]$StaticOnly,
    [switch]$RequireModels,
    [switch]$RequireExtensions,
    [switch]$RequireSupportAssets,
    [switch]$SkipArtifactHashes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')
. (Join-Path $PSScriptRoot 'download-models.ps1') -LibraryOnly

$root = Get-ProjectRoot
$version = Read-Json (Join-Path $root 'comfyui-version.json')
$manifest = Read-Json (Join-Path $root 'model-manifest.json')
$supportManifest = Read-Json (Join-Path $root 'support-model-manifest.json')
$extensionsManifest = Read-Json (Join-Path $root 'extensions-manifest.json')
$python = Join-Path $root '.venv\Scripts\python.exe'
$comfyPath = Join-Path $root 'ComfyUI'
$modelsRoot = Join-Path $root 'models'
$workflowRoot = Join-Path $root 'workflows\ui'
$appsRoot = Join-Path $root 'workflows\apps'
$catalog = Read-Json (Join-Path $root 'workflow-catalog.json')

Assert-Condition (-not $SkipArtifactHashes -or $StaticOnly) '-SkipArtifactHashes requires -StaticOnly'
Assert-Condition (-not $RequireSupportAssets -or -not $SkipArtifactHashes) '-RequireSupportAssets requires artifact hashes'

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

$validSupportArtifacts = $missingSupportArtifacts = $invalidSupportArtifacts = 0
if (-not $SkipArtifactHashes) {
    foreach ($artifact in $supportManifest.artifacts) {
        $path = Join-Path $modelsRoot $artifact.target.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path)) {
            $missingSupportArtifacts++
        }
        elseif (Test-Artifact -Path $path -Bytes $artifact.bytes -Sha256 $artifact.sha256) {
            $validSupportArtifacts++
        }
        else {
            $invalidSupportArtifacts++
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

$validApps = 0
foreach ($app in $catalog.apps) {
    $path = Join-Path $appsRoot $app.file.Replace('/', [IO.Path]::DirectorySeparatorChar)
    Assert-Condition (Test-Path -LiteralPath $path) "Missing Studio app: $($app.id)"
    try {
        $workflow = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($workflow.version -eq 0.4 -and $workflow.extra.linearMode -eq $true) {
            $validApps++
        }
    }
    catch {
        throw "Invalid Studio app JSON: $($app.id)"
    }
}
Assert-Condition ($validApps -eq 15) "Expected fifteen valid Studio apps; found $validApps"

$verifiedExtensions = 0
if ($RequireExtensions) {
    foreach ($extension in $extensionsManifest.extensions) {
        $extensionPath = Join-Path $comfyPath "custom_nodes\$($extension.name)"
        Assert-Condition (Test-Path -LiteralPath (Join-Path $extensionPath '.git')) "$($extension.id) checkout is missing"
        $origin = (& git -C $extensionPath remote get-url origin).Trim()
        $extensionCommit = (& git -C $extensionPath rev-parse HEAD).Trim()
        $dirty = ((& git -C $extensionPath status --porcelain) -join '')
        Assert-Condition ($origin -eq $extension.repository) "Unexpected $($extension.id) origin: $origin"
        Assert-Condition ($extensionCommit -eq $extension.commit) "Unexpected $($extension.id) commit: $extensionCommit"
        Assert-Condition ([string]::IsNullOrWhiteSpace($dirty)) "$($extension.id) has local changes"
        $verifiedExtensions++
    }

    $studioLink = Join-Path $comfyPath 'custom_nodes\comfyui_local_studio'
    Assert-Condition (Test-Path -LiteralPath $studioLink) 'Local Studio node link is missing'
    $studioItem = Get-Item -LiteralPath $studioLink -Force
    Assert-Condition (($studioItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Local Studio node is not linked into ComfyUI'
}

$httpHealthy = $false
$systemStats = $null
$requiredNodes = 0
if (-not $StaticOnly) {
    $systemStats = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/system_stats' -TimeoutSec 10
    $httpHealthy = $null -ne $systemStats
    Assert-Condition $httpHealthy 'ComfyUI health endpoint did not respond'

    $expectedServed = @($catalog.apps | ForEach-Object { "ComfyUI Local Studio/$($_.file)" })
    $workflowListAttempts = 3
    $served = @()
    for ($attempt = 1; $attempt -le $workflowListAttempts; $attempt++) {
        # Invoke-RestMethod returns its JSON array as one non-enumerated object
        # when it is wrapped directly in @(...). Capture it first so PowerShell
        # flattens the string array during the second assignment.
        $workflowResponse = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/api/userdata?dir=workflows&recurse=true' -TimeoutSec 10
        $served = @($workflowResponse)
        $missingServed = @($expectedServed | Where-Object { $_ -notin $served })
        if ($missingServed.Count -eq 0) { break }
        if ($attempt -lt $workflowListAttempts) { Start-Sleep -Seconds 1 }
    }
    foreach ($app in $catalog.apps) {
        $servedPath = "ComfyUI Local Studio/$($app.file)"
        Assert-Condition ($servedPath -in $served) "Studio app is not served: $($app.id)"
    }

    if ($RequireExtensions) {
        $objectInfo = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/object_info' -TimeoutSec 30
        $nodeTypes = @($extensionsManifest.extensions.requiredNodeTypes) + @(
            'StudioResolutionPreset',
            'StudioPhotoStylePrompt',
            'StudioAnimeStylePrompt',
            'StudioGeneralStylePrompt',
            'StudioControlPreset',
            'StudioSDXLLoraLoader',
            'StudioZImageLoraLoader',
            'StudioFlux2LoraLoader'
        )
        foreach ($nodeType in $nodeTypes | Select-Object -Unique) {
            Assert-Condition ($null -ne $objectInfo.PSObject.Properties[$nodeType]) "Required node is not registered: $nodeType"
            $requiredNodes++
        }
    }
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
    supportArtifacts = [ordered]@{
        records = $supportManifest.artifacts.Count
        hashesSkipped = [bool]$SkipArtifactHashes
        valid = $validSupportArtifacts
        missing = $missingSupportArtifacts
        invalid = $invalidSupportArtifacts
    }
    uiWorkflows = $validWorkflows
    studioApps = $validApps
    extensions = $verifiedExtensions
    requiredNodes = $requiredNodes
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
if ($SkipArtifactHashes) {
    Write-Output "Support artifact records: $($supportManifest.artifacts.Count); hash checks skipped"
}
else {
    Write-Output "Support artifacts: $validSupportArtifacts valid, $missingSupportArtifacts missing, $invalidSupportArtifacts invalid"
}
Write-Output "UI workflows: $validWorkflows valid"
Write-Output "Studio apps: $validApps valid"
if ($RequireExtensions) { Write-Output "Extensions: $verifiedExtensions pinned" }
if (-not $StaticOnly) { Write-Output 'HTTP: healthy at http://127.0.0.1:8188' }
if (-not $StaticOnly -and $RequireExtensions) { Write-Output "Required nodes: $requiredNodes registered" }

if (-not $SkipArtifactHashes) {
    Assert-Condition ($invalidArtifacts -eq 0) "$invalidArtifacts model artifacts are invalid"
    Assert-Condition ($invalidSupportArtifacts -eq 0) "$invalidSupportArtifacts support artifacts are invalid"
    if ($RequireModels -or -not $StaticOnly) {
        Assert-Condition ($missingArtifacts -eq 0) "$missingArtifacts model artifacts are missing"
    }
    if ($RequireSupportAssets) {
        Assert-Condition ($missingSupportArtifacts -eq 0) "$missingSupportArtifacts support artifacts are missing"
    }
}
