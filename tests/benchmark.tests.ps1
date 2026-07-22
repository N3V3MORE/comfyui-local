$projectRoot = Split-Path -Parent $PSScriptRoot
$benchmarkScript = Join-Path $projectRoot 'scripts\benchmark.ps1'
$models = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\models.json') -Raw | ConvertFrom-Json).models
$presets = (Get-Content -LiteralPath (Join-Path $projectRoot 'config\resolutions.json') -Raw | ConvertFrom-Json).resolutions
$scenarios = Get-Content -LiteralPath (Join-Path $projectRoot 'config\benchmark-scenarios.json') -Raw | ConvertFrom-Json

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

Test-Case 'benchmark delegates prompt materialization to semantic Python code' {
    $source = Get-Content -LiteralPath $benchmarkScript -Raw

    Assert-True ($source -match 'python.+-m comfy_local prompt') 'benchmark invokes the semantic prompt CLI'
    Assert-True ($source -notmatch 'Set-BenchmarkInputs') 'benchmark does not mutate API graphs in PowerShell'
    Assert-True ($source -notmatch 'workflowProfile') 'benchmark does not select numeric fixtures by legacy profile'
}

Test-Case 'proof matrix derives models and orientations from focused configuration' {
    . $benchmarkScript -LibraryOnly
    $matrix = @(Get-ProofMatrix -Models $models -Presets $presets -PresetIds $scenarios.orientationProof.presetIds)
    $expectedCount = $models.Count * $scenarios.orientationProof.presetIds.Count

    Assert-Equal $expectedCount $matrix.Count 'proof job count'
    foreach ($presetId in $scenarios.orientationProof.presetIds) {
        Assert-Equal $models.Count @($matrix | Where-Object presetId -eq $presetId).Count "$presetId job count"
    }
}

Test-Case 'benchmark exposes separate performance and quality execution modes' {
    $source = Get-Content -LiteralPath $benchmarkScript -Raw

    Assert-True ($source -match "ValidateSet\('orientation',\s*'performance',\s*'quality'\)") 'benchmark exposes three explicit suites'
    Assert-True ($source -match '/free') 'performance benchmark unloads models before cold runs'
    Assert-True ($source -match 'Get-Median') 'benchmark reports median timings'
    Assert-True ($source -match 'quality-ratings\.csv') 'quality suite creates a blind rating sheet'
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

Test-Case 'benchmark retries a transient history request' {
    . $benchmarkScript -LibraryOnly
    $script:benchmarkAttempts = 0
    $history = Get-ComfyHistory -PromptId 'prompt-1' -Server 'http://127.0.0.1:8188' -Request {
        param($uri)
        $script:benchmarkAttempts++
        if ($script:benchmarkAttempts -eq 1) { throw 'transient connection failure' }
        return '{"prompt-1":{"status":{"completed":true}}}' | ConvertFrom-Json
    }

    Assert-Equal 2 $script:benchmarkAttempts 'history request retries once'
    Assert-True ($null -ne (Get-ComfyHistoryEntry -History $history -PromptId 'prompt-1')) 'retry returns history response'
}

Test-Case 'benchmark continues polling after one exhausted history retry group' {
    . $benchmarkScript -LibraryOnly
    $script:benchmarkPollAttempts = 0
    $completed = Wait-ComfyPrompt -PromptId 'prompt-1' -Server 'http://127.0.0.1:8188' -TimeoutMinutes 1 -HistoryRequest {
        param($uri)
        $script:benchmarkPollAttempts++
        if ($script:benchmarkPollAttempts -le 3) { throw 'temporary server failure' }
        return '{"prompt-1":{"status":{"completed":true},"outputs":{"save":{"images":[{"filename":"result.png","subfolder":"","type":"output"}]}}}}' | ConvertFrom-Json
    }

    Assert-Equal 4 $script:benchmarkPollAttempts 'polling continues after the bounded inner retry group'
    Assert-Equal 'result.png' $completed.images[0].filename 'completed prompt returns its image'
}

Test-Case 'benchmark validates Comfy output paths before copying them locally' {
    $source = Get-Content -LiteralPath $benchmarkScript -Raw

    Assert-True ($source -match 'Assert-SafeRelativePath') 'benchmark validates returned image paths'
}

Test-Case 'benchmark accepts Comfy images in the output root' {
    . $benchmarkScript -LibraryOnly
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("comfyui-local-image-test-" + [guid]::NewGuid())
    try {
        New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
        $source = Join-Path $testRoot 'pose.png'
        [IO.File]::WriteAllText($source, 'image')
        $image = [pscustomobject]@{ subfolder = ''; filename = 'pose.png' }

        $copied = Copy-ComfyImage -Image $image -ComfyOutputRoot $testRoot -DestinationRoot (Join-Path $testRoot 'proof') -ModelId 'model'
        Assert-True (Test-Path -LiteralPath $copied) 'root output image is copied'
    }
    finally {
        if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    }
}

Test-Case 'VRAM monitoring keeps the highest valid sample' {
    . $benchmarkScript -LibraryOnly
    $samples = @('1008', '4921', 'not-a-number', '4380')

    Assert-Equal 4921 (Get-PeakVramMiB -Samples $samples) 'peak GPU memory sample'
    Assert-Equal 0 (Get-PeakVramMiB -Samples @()) 'empty GPU memory samples'
}
