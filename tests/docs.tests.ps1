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

Test-Case 'comparison documents all six models and measured 8 GB results' {
    $comparisonPath = Join-Path $projectRoot 'MODEL_COMPARISON.md'
    Assert-True (Test-Path -LiteralPath $comparisonPath) 'comparison exists'
    $comparison = Get-Content -LiteralPath $comparisonPath -Raw
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'model-manifest.json') -Raw | ConvertFrom-Json

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

    Assert-Equal 18 $evidence.proofImages 'proof image count'
    Assert-Equal 6 $evidence.models.Count 'benchmarked model count'
    Assert-Equal 3 $evidence.presets.Count 'benchmarked preset count'
    Assert-True ($evidence.models.peakVramMiB -notcontains 0) 'every model has observed VRAM data'
}
