$projectRoot = Split-Path -Parent $PSScriptRoot
$compileScript = Join-Path $projectRoot 'scripts\compile.ps1'
$syncScript = Join-Path $projectRoot 'scripts\sync-studio-apps.ps1'
$installScript = Join-Path $projectRoot 'scripts\install-workflows.ps1'
$assetScript = Join-Path $projectRoot 'scripts\copy-bundled-inputs.ps1'

Test-Case 'workflow compiler CLI writes the declared catalog' {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("comfy-compiler-" + [guid]::NewGuid())
    try {
        & $compileScript -OutputRoot $tempRoot | Out-Null
        $specs = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\workflow-specs.json') -Raw | ConvertFrom-Json).apps

        Assert-Equal $specs.Count @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'workflows\apps') -Recurse -Filter '*.app.json').Count 'compiled app count'
        Assert-Equal 4 @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'workflows\ui') -Filter '*.json').Count 'compiled UI workflow count'
        Assert-Equal 3 @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'workflows\api') -Filter '*.json').Count 'compiled API prompt count'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

Test-Case 'Studio compatibility sync contains orchestration only' {
    $source = Get-Content -LiteralPath $syncScript -Raw

    foreach ($forbidden in @(
        'CheckpointLoaderSimple',
        'New-AppInput',
        'Set-AppData',
        'Write-Workflow',
        'ConvertFrom-Json',
        'Copy-Item',
        'widgets_values',
        'last_node_id'
    )) {
        Assert-True ($source -notmatch [regex]::Escape($forbidden)) "sync wrapper must not contain $forbidden"
    }
    foreach ($required in @('compile.ps1', 'copy-bundled-inputs.ps1', 'install-workflows.ps1')) {
        Assert-True ($source -match [regex]::Escape($required)) "sync wrapper invokes $required"
    }
}

Test-Case 'workflow installation and bundled input copy are separate scripts' {
    Assert-True (Test-Path -LiteralPath $installScript) 'workflow installer exists'
    Assert-True (Test-Path -LiteralPath $assetScript) 'bundled input copier exists'

    $installSource = Get-Content -LiteralPath $installScript -Raw
    $assetSource = Get-Content -LiteralPath $assetScript -Raw
    Assert-True ($installSource -match 'Copy-Item') 'installer copies compiled workflows'
    Assert-True ($installSource -notmatch 'studio-reference\.webp') 'installer does not own bundled inputs'
    Assert-True ($assetSource -match 'studio-reference\.webp') 'asset copier owns the bundled reference image'
    Assert-True ($assetSource -notmatch 'workflow-specs\.json') 'asset copier does not install workflows'
}

Test-Case 'workflow installer reconciles obsolete Studio app files' {
    $source = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\install-workflows.ps1') -Raw

    Assert-True ($source -match 'Remove-Item') 'installer removes stale Studio workflow files'
}
