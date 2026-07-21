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
