$projectRoot = Split-Path -Parent $PSScriptRoot

Test-Case 'defines seven model-safe aspect ratios' {
    $path = Join-Path $projectRoot 'config\resolutions.json'
    $ratios = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).resolutions

    Assert-Equal 7 $ratios.Count 'preset count'
    Assert-Equal '1024x1024' $ratios[0].id 'square preset is first'
    Assert-Equal 1024 $ratios[0].width 'square width'
    Assert-Equal 1024 $ratios[0].height 'square height'
    foreach ($preset in $ratios) {
        Assert-True (($preset.width % 64) -eq 0) "$($preset.id) width must be divisible by 64"
        Assert-True (($preset.height % 64) -eq 0) "$($preset.id) height must be divisible by 64"
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'config\aspect-ratios.json'))) 'legacy duplicate resolution file is removed'
}

Test-Case 'pins the ComfyUI and CUDA environment' {
    $path = Join-Path $projectRoot 'comfyui-version.json'
    $version = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    Assert-Equal 'd0fec2ef7e7086533fde261de3fdb88289bdca9e' $version.commit 'ComfyUI commit'
    Assert-Equal '3.13' $version.python 'Python version'
    Assert-Equal '2.11.0+cu130' $version.torch 'Torch version'
    Assert-Equal '0.26.0+cu130' $version.torchvision 'Torchvision version'
    Assert-Equal '2.11.0+cu130' $version.torchaudio 'Torchaudio version'
}

Test-Case 'defines six models and ten immutable artifacts' {
    $models = Get-Content -LiteralPath (Join-Path $projectRoot 'config\models.json') -Raw | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'config\artifacts.json') -Raw | ConvertFrom-Json
    $coreArtifacts = @($manifest.artifacts | Where-Object role -eq 'core')

    Assert-Equal 6 $models.models.Count 'model count'
    Assert-Equal 10 $coreArtifacts.Count 'artifact count'
    $payloadBytes = ($coreArtifacts | Measure-Object -Property bytes -Sum).Sum
    Assert-Equal 44499084381 $payloadBytes 'artifact payload bytes'

    foreach ($artifact in $coreArtifacts) {
        Assert-True ($artifact.url -match '/resolve/[0-9a-f]{40}/') "$($artifact.id) URL must be revision-pinned"
        Assert-True ($artifact.sha256 -match '^[0-9a-f]{64}$') "$($artifact.id) must have a SHA-256"
        Assert-True ([long]$artifact.bytes -gt 0) "$($artifact.id) must have a positive byte size"
        Assert-True (-not [IO.Path]::IsPathRooted($artifact.target)) "$($artifact.id) target must be relative"
    }
}

Test-Case 'vendors canonical workflows instead of downloading mutable sources' {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'workflow-sources.json'))) 'legacy workflow source manifest is removed'
    foreach ($name in @('sdxl-base.json', 'z-image-turbo.json', 'flux2-klein.json')) {
        $path = Join-Path $projectRoot "vendor\workflows\$name"
        Assert-True (Test-Path -LiteralPath $path) "$name is vendored"
        Assert-True ((Get-Content -LiteralPath $path -Raw) -notmatch '/resolve/main') "$name has no moving model source"
    }
}

Test-Case 'legacy duplicate manifests are removed' {
    foreach ($name in @('model-manifest.json', 'support-model-manifest.json', 'workflow-catalog.json')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot $name))) "$name is removed"
    }
}

Test-Case 'pins all three CUDA packages in requirements input' {
    $path = Join-Path $projectRoot 'requirements.in'
    $requirements = @(Get-Content -LiteralPath $path)

    Assert-True ($requirements -contains 'torch==2.11.0+cu130') 'Torch must be exact'
    Assert-True ($requirements -contains 'torchvision==0.26.0+cu130') 'Torchvision must be exact'
    Assert-True ($requirements -contains 'torchaudio==2.11.0+cu130') 'Torchaudio must be exact'
}

Test-Case 'pins extension dependency conflicts in the shared lock input' {
    $path = Join-Path $projectRoot 'requirements.in'
    $requirements = @(Get-Content -LiteralPath $path)

    Assert-True ($requirements -contains 'ultralytics==8.4.103') 'Ultralytics must be exact'
    Assert-True ($requirements -contains 'mediapipe==0.10.35') 'MediaPipe must be exact'
    Assert-True ($requirements -contains 'onnxruntime-gpu==1.27.0') 'ONNX Runtime GPU must be exact'
    Assert-True ($requirements -contains 'opencv-python==5.0.0.93') 'OpenCV must be exact'
    Assert-True ($requirements -contains 'opencv-python-headless==5.0.0.93') 'headless OpenCV must be exact'
    Assert-True ($requirements -contains 'opencv-contrib-python==5.0.0.93') 'contrib OpenCV must be exact'
    Assert-True ($requirements -contains 'sam-2 @ git+https://github.com/facebookresearch/sam2@2b90b9f5ceec907a1c18123530e92e794ad901a4') 'SAM2 Git dependency must be immutable'
}
