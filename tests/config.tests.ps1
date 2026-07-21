$projectRoot = Split-Path -Parent $PSScriptRoot

Test-Case 'defines seven model-safe aspect ratios' {
    $path = Join-Path $projectRoot 'config\aspect-ratios.json'
    $ratios = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    Assert-Equal 7 $ratios.presets.Count 'preset count'
    Assert-Equal '1024x1024' $ratios.presets[0].id 'square preset is first'
    Assert-Equal 1024 $ratios.presets[0].width 'square width'
    Assert-Equal 1024 $ratios.presets[0].height 'square height'
    foreach ($preset in $ratios.presets) {
        Assert-True (($preset.width % 64) -eq 0) "$($preset.id) width must be divisible by 64"
        Assert-True (($preset.height % 64) -eq 0) "$($preset.id) height must be divisible by 64"
    }
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
    $path = Join-Path $projectRoot 'model-manifest.json'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    Assert-Equal 6 $manifest.models.Count 'model count'
    Assert-Equal 10 $manifest.artifacts.Count 'artifact count'
    $payloadBytes = ($manifest.artifacts | Measure-Object -Property bytes -Sum).Sum
    Assert-Equal 44499084381 $payloadBytes 'artifact payload bytes'

    foreach ($artifact in $manifest.artifacts) {
        Assert-True ($artifact.url -match '/resolve/[0-9a-f]{40}/') "$($artifact.id) URL must be revision-pinned"
        Assert-True ($artifact.sha256 -match '^[0-9a-f]{64}$') "$($artifact.id) must have a SHA-256"
        Assert-True ([long]$artifact.bytes -gt 0) "$($artifact.id) must have a positive byte size"
        Assert-True (-not [IO.Path]::IsPathRooted($artifact.target)) "$($artifact.id) target must be relative"
    }
}

Test-Case 'pins official workflow sources' {
    $path = Join-Path $projectRoot 'workflow-sources.json'
    $sources = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    Assert-True ($sources.sdxl -match '/24d928409605c3a01c0fb9857d024c7bb1572597/') 'SDXL source is pinned'
    Assert-True ($sources.zImage -match '/93f3058d5ad87d83c5eab7c0eabd734738376816/') 'Z-Image source is pinned'
    Assert-True ($sources.flux2 -match '/93f3058d5ad87d83c5eab7c0eabd734738376816/') 'FLUX.2 source is pinned'
}

Test-Case 'pins all three CUDA packages in requirements input' {
    $path = Join-Path $projectRoot 'requirements.in'
    $requirements = Get-Content -LiteralPath $path -Raw

    Assert-True ($requirements -match '(?m)^torch==2\.11\.0\+cu130$') 'Torch must be exact'
    Assert-True ($requirements -match '(?m)^torchvision==0\.26\.0\+cu130$') 'Torchvision must be exact'
    Assert-True ($requirements -match '(?m)^torchaudio==2\.11\.0\+cu130$') 'Torchaudio must be exact'
}

Test-Case 'pins extension dependency conflicts in the shared lock input' {
    $path = Join-Path $projectRoot 'requirements.in'
    $requirements = Get-Content -LiteralPath $path -Raw

    Assert-True ($requirements -match '(?m)^ultralytics==8\.4\.103$') 'Ultralytics must be exact'
    Assert-True ($requirements -match '(?m)^mediapipe==0\.10\.35$') 'MediaPipe must be exact'
    Assert-True ($requirements -match '(?m)^onnxruntime-gpu==1\.27\.0$') 'ONNX Runtime GPU must be exact'
    Assert-True ($requirements -match '(?m)^opencv-python==5\.0\.0\.93$') 'OpenCV must be exact'
    Assert-True ($requirements -match '(?m)^opencv-python-headless==5\.0\.0\.93$') 'headless OpenCV must be exact'
    Assert-True ($requirements -match '(?m)^opencv-contrib-python==5\.0\.0\.93$') 'contrib OpenCV must be exact'
    Assert-True ($requirements -match 'facebookresearch/sam2@2b90b9f5ceec907a1c18123530e92e794ad901a4') 'SAM2 Git dependency must be immutable'
}
