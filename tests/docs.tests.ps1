$projectRoot = Split-Path -Parent $PSScriptRoot

Test-Case 'README gives a direct local launch and orientation path' {
    $readmePath = Join-Path $projectRoot 'README.md'
    Assert-True (Test-Path -LiteralPath $readmePath) 'README exists'
    $readme = Get-Content -LiteralPath $readmePath -Raw

    Assert-True ($readme -match 'scripts\\start\.ps1') 'README has the start command'
    Assert-True ($readme -match 'http://127\.0\.0\.1:8188') 'README has the local URL'
    Assert-True ($readme -match '1024.+1024') 'README includes square dimensions'
    Assert-True ($readme -match '1216.+832') 'README includes landscape dimensions'
    Assert-True ($readme -match '832.+1216') 'README includes portrait dimensions'
}

Test-Case 'README explains the isolated Opera App Mode workflow' {
    $readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw

    Assert-True ($readme -match 'ComfyUI Local Studio') 'README names the installed app collection'
    Assert-True ($readme -match 'RealVisXL Natural Photo') 'README lists a core create app'
    Assert-True ($readme -match 'SDXL Canny Control') 'README lists an advanced control app'
    Assert-True ($readme -match 'Photo Upscale 2x') 'README lists an image-input app'
    Assert-True ($readme -match 'mat1 and mat2 shapes cannot be multiplied') 'README explains the reported model-family error'
    Assert-True ($readme -match 'select or upload') 'README explains image input in App Mode'
}

Test-Case 'README does not overstate advanced-app smoke evidence as full generation proof' {
    $readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw

    Assert-True ($readme -notmatch 'have completed real prompts through the live local server') 'README does not claim smoke evidence proves every advanced workflow'
    Assert-True ($readme -match 'not a substitute for an end-to-end generation record') 'README distinguishes smoke checks from full generation proof'
}

Test-Case 'README documents the semantic compiler and focused configuration' {
    $readme = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw

    Assert-True ($readme -match 'scripts\\compile\.ps1') 'README documents the compiler entrypoint'
    Assert-True ($readme -match 'studio_key') 'README explains semantic node identity'
    foreach ($name in @('models.json', 'artifacts.json', 'workflow-specs.json', 'resolutions.json', 'benchmark-scenarios.json')) {
        Assert-True ($readme -match [regex]::Escape($name)) "README documents $name"
    }
    foreach ($legacy in @('model-manifest.json', 'support-model-manifest.json', 'workflow-catalog.json', 'aspect-ratios.json')) {
        Assert-True ($readme -notmatch [regex]::Escape($legacy)) "README does not document removed $legacy"
    }
}

Test-Case 'comparison documents all six models and measured 8 GB results' {
    $comparisonPath = Join-Path $projectRoot 'MODEL_COMPARISON.md'
    Assert-True (Test-Path -LiteralPath $comparisonPath) 'comparison exists'
    $comparison = Get-Content -LiteralPath $comparisonPath -Raw
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'config\models.json') -Raw | ConvertFrom-Json

    foreach ($model in $manifest.models) {
        Assert-True ($comparison.Contains($model.name)) "comparison includes $($model.name)"
    }
    Assert-True ($comparison -match 'RTX 5060 Laptop GPU') 'comparison names the measured GPU'
    Assert-True ($comparison -match 'license') 'comparison includes license guidance'
}

Test-Case 'benchmark evidence records the complete proof matrix' {
    $evidencePath = Join-Path $projectRoot 'docs\evidence\benchmark-summary.json'
    Assert-True (Test-Path -LiteralPath $evidencePath) 'benchmark evidence exists'
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json

    $modelCount = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\models.json') -Raw | ConvertFrom-Json).models.Count
    $presetCount = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\benchmark-scenarios.json') -Raw | ConvertFrom-Json).orientationProof.presetIds.Count
    Assert-Equal ($modelCount * $presetCount) $evidence.proofImages 'proof image count'
    Assert-Equal $modelCount $evidence.models.Count 'benchmarked model count'
    Assert-Equal $presetCount $evidence.presets.Count 'benchmarked preset count'
    Assert-True ($evidence.models.peakVramMiB -notcontains 0) 'every model has observed VRAM data'
}
