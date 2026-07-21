$projectRoot = Split-Path -Parent $PSScriptRoot
$setupScript = Join-Path $projectRoot 'scripts\setup.ps1'

Test-Case 'setup validation checks the required local prerequisites' {
    $output = (& $setupScript -ValidateOnly) | Out-String

    foreach ($expected in @('Git', 'uv', 'curl.exe', 'nvidia-smi', 'Python 3.13', 'NVIDIA GeForce RTX 5060 Laptop GPU', 'free disk space')) {
        Assert-True ($output -match [regex]::Escape($expected)) "validation output must name $expected"
    }
}

Test-Case 'setup renders the external model path configuration' {
    $yaml = ((& $setupScript -PrintExtraModelPaths) -join "`n").Trim()
    $expected = @'
comfyui_local:
  base_path: C:/Users/Sushmit/Desktop/Code/comfyui-local/models
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  text_encoders: text_encoders
  vae: vae
'@.Trim()

    Assert-Equal $expected $yaml 'external model paths YAML'
}

Test-Case 'setup synchronizes packages from the CUDA wheel index' {
    $command = ((& $setupScript -PrintSyncCommand) -join ' ').Trim()

    Assert-True ($command -match '--extra-index-url https://download\.pytorch\.org/whl/cu130') 'sync command includes CUDA index'
    Assert-True ($command -match '--index-strategy unsafe-best-match') 'sync command selects across indexes'
    Assert-True ($command -match 'requirements\.lock\.txt') 'sync command uses the lock file'
}

Test-Case 'setup reuses an existing virtual environment' {
    $action = ((& $setupScript -PrintVenvAction) -join ' ').Trim()
    $venvPython = Join-Path $projectRoot '.venv\Scripts\python.exe'

    if (Test-Path -LiteralPath $venvPython) {
        Assert-Equal 'reuse' $action 'existing virtual environment action'
    }
    else {
        Assert-Equal 'create' $action 'missing virtual environment action'
    }
}

Test-Case 'setup prints the exact extension and local-node installation plan' {
    $output = @(& $setupScript -PrintExtensionPlan)

    Assert-Equal 6 $output.Count 'extension plan line count'
    foreach ($expected in @(
        'rgthree-comfy@27b4f4cdcf3b127c29d5d8135ac1536ecbd4c383',
        'comfyui-impact-pack@429d0159ad429e64d2b3916e6e7be9c22d025c3c',
        'comfyui-impact-subpack@50c7b71a6a224734cc9b21963c6d1926816a97f1',
        'comfyui-controlnet-aux@e8b689a513c3e6b63edc44066560ca5919c0576e',
        'comfyui-ipadapter-plus@a0f451a5113cf9becb0847b92884cb10cbdec0ef',
        'comfyui-local-studio@tracked'
    )) {
        Assert-True ($expected -in $output) "extension plan must contain $expected"
    }
}

Test-Case 'setup blocks extension hooks from downloading unmanifested models' {
    $output = @(& $setupScript -PrintExtensionHookPolicy)

    Assert-True ($output -contains "COMFYUI_PATH=$projectRoot\ComfyUI") 'hook policy exposes the pinned ComfyUI path'
    Assert-True ($output -contains "COMFYUI_MODEL_PATH=$projectRoot\models") 'hook policy redirects models to the project model store'
    Assert-True ($output -contains "SKIP_DOWNLOAD_MARKER=$projectRoot\ComfyUI\custom_nodes\skip_download_model") 'hook policy creates the supported download opt-out marker'
}

Test-Case 'setup installs the Studio app catalog' {
    $source = Get-Content -LiteralPath $setupScript -Raw

    Assert-True ($source -match "sync-studio-apps\.ps1") 'setup invokes the deterministic Studio app sync'
}
