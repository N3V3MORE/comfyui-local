$projectRoot = Split-Path -Parent $PSScriptRoot
$benchmarkScript = Join-Path $projectRoot 'scripts\benchmark.ps1'
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'model-manifest.json') -Raw | ConvertFrom-Json
$presets = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\resolutions.json') -Raw | ConvertFrom-Json).resolutions

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

Test-Case 'queued prompts tolerate an empty history response' {
    . $benchmarkScript -LibraryOnly
    $emptyHistory = '{}' | ConvertFrom-Json
    $completedHistory = '{"prompt-1":{"status":{"completed":true}}}' | ConvertFrom-Json

    Assert-True ($null -eq (Get-ComfyHistoryEntry -History $emptyHistory -PromptId 'prompt-1')) 'queued prompt has no history entry yet'
    Assert-True ((Get-ComfyHistoryEntry -History $completedHistory -PromptId 'prompt-1').status.completed) 'completed prompt entry is returned'
}

Test-Case 'completed prompts ignore node outputs that do not contain images' {
    . $benchmarkScript -LibraryOnly
    $outputs = '{"pose":{"pose_keypoint":[{"people":[]}]},"save":{"images":[{"filename":"pose.png","subfolder":"","type":"output"}]}}' | ConvertFrom-Json
    $images = @(Get-ComfyImages -Outputs $outputs)

    Assert-Equal 1 $images.Count 'collected image count'
    Assert-Equal 'pose.png' $images[0].filename 'collected image filename'
}

Test-Case 'VRAM monitoring keeps the highest valid sample' {
    . $benchmarkScript -LibraryOnly
    $samples = @('1008', '4921', 'not-a-number', '4380')

    Assert-Equal 4921 (Get-PeakVramMiB -Samples $samples) 'peak GPU memory sample'
    Assert-Equal 0 (Get-PeakVramMiB -Samples @()) 'empty GPU memory samples'
}
