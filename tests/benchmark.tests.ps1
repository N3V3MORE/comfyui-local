$projectRoot = Split-Path -Parent $PSScriptRoot
$benchmarkScript = Join-Path $projectRoot 'scripts\benchmark.ps1'
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'model-manifest.json') -Raw | ConvertFrom-Json
$presets = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\aspect-ratios.json') -Raw | ConvertFrom-Json).presets

Test-Case 'API fixtures cover the three pinned workflow profiles' {
    $fixtureNames = @('sdxl.json', 'z_image.json', 'flux2.json')
    foreach ($fixtureName in $fixtureNames) {
        $path = Join-Path $projectRoot "workflows\api\$fixtureName"
        Assert-True (Test-Path -LiteralPath $path) "$fixtureName exists"
        $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $nodes = @($fixture.PSObject.Properties | ForEach-Object Value)
        Assert-True ($nodes.Count -ge 7) "$fixtureName has a complete graph"
        Assert-True (@($nodes | Where-Object class_type -eq 'SaveImage').Count -eq 1) "$fixtureName saves one output"
    }
}

Test-Case 'benchmark mutation maps every model to its profile and canvas' {
    . $benchmarkScript -LibraryOnly
    $canvas = $presets | Where-Object id -eq '1216x832'

    foreach ($model in $manifest.models) {
        $fixturePath = Join-Path $projectRoot "workflows\api\$($model.workflowProfile).json"
        $workflow = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
        Set-BenchmarkInputs -Workflow $workflow -Model $model -Canvas $canvas -Seed 42 -FilenamePrefix "proof/$($model.id)"

        $modelLoader = $workflow.PSObject.Properties.Value | Where-Object class_type -in @('CheckpointLoaderSimple', 'UNETLoader')
        $latent = $workflow.PSObject.Properties.Value | Where-Object class_type -in @('EmptyLatentImage', 'EmptySD3LatentImage', 'EmptyFlux2LatentImage')
        $save = $workflow.PSObject.Properties.Value | Where-Object class_type -eq 'SaveImage'

        Assert-True ($null -ne $modelLoader) "$($model.id) selects a model loader"
        Assert-Equal 1216 $latent.inputs.width "$($model.id) width"
        Assert-Equal 832 $latent.inputs.height "$($model.id) height"
        Assert-Equal "proof/$($model.id)" $save.inputs.filename_prefix "$($model.id) output prefix"
    }
}

Test-Case 'proof matrix is six models by three orientations' {
    . $benchmarkScript -LibraryOnly
    $matrix = @(Get-ProofMatrix -Models $manifest.models -Presets $presets)

    Assert-Equal 18 $matrix.Count 'proof job count'
    Assert-Equal 6 @($matrix | Where-Object orientation -eq 'square').Count 'square job count'
    Assert-Equal 6 @($matrix | Where-Object orientation -eq 'landscape').Count 'landscape job count'
    Assert-Equal 6 @($matrix | Where-Object orientation -eq 'portrait').Count 'portrait job count'
}
