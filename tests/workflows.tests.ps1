$projectRoot = Split-Path -Parent $PSScriptRoot
$workflowRoot = Join-Path $projectRoot 'workflows\ui'

$expectations = @(
    @{ File = 'realistic-sdxl.json'; Required = @('RealVisXL_V5.0_fp16.safetensors', '1024', '30', 'Canvas') },
    @{ File = 'anime-sdxl.json'; Required = @('animagine-xl-4.0-opt.safetensors', '1024', '28', 'Canvas') },
    @{ File = 'z-image-turbo.json'; Required = @('z_image_turbo_nvfp4.safetensors', 'qwen_3_4b_fp4_mixed.safetensors', 'ae.safetensors', '1024', 'Canvas') },
    @{ File = 'flux2-klein.json'; Required = @('flux-2-klein-4b-fp8.safetensors', 'qwen_3_4b_fp4_flux2.safetensors', 'flux2-vae.safetensors', '1024', 'Canvas') }
)

foreach ($expectation in $expectations) {
    Test-Case "$($expectation.File) is a pinned core workflow with canvas controls" {
        $path = Join-Path $workflowRoot $expectation.File
        $raw = Get-Content -LiteralPath $path -Raw
        $workflow = $raw | ConvertFrom-Json

        Assert-Equal 0.4 $workflow.version "$($expectation.File) workflow version"
        Assert-True ($raw -notmatch 'resolve/main') "$($expectation.File) must not contain moving model URLs"
        Assert-True ($raw -notmatch 'http://') "$($expectation.File) must not contain insecure URLs"
        Assert-True (@($workflow.groups | Where-Object title -match '^Canvas').Count -eq 1) "$($expectation.File) must have one Canvas group"
        foreach ($required in $expectation.Required) {
            Assert-True ($raw.Contains($required)) "$($expectation.File) must contain $required"
        }
    }
}

Test-Case 'modern workflows contain only their selected generation subgraph' {
    $z = Get-Content -LiteralPath (Join-Path $workflowRoot 'z-image-turbo.json') -Raw | ConvertFrom-Json
    $flux = Get-Content -LiteralPath (Join-Path $workflowRoot 'flux2-klein.json') -Raw | ConvertFrom-Json

    Assert-Equal 1 $z.definitions.subgraphs.Count 'Z-Image subgraph count'
    Assert-Equal 1 $flux.definitions.subgraphs.Count 'FLUX.2 subgraph count'
    Assert-True (@($z.nodes | Where-Object type -eq 'MarkdownNote').Count -eq 0) 'Z-Image moving link note removed'
    Assert-True (@($flux.nodes | Where-Object type -eq 'MarkdownNote').Count -eq 0) 'FLUX.2 moving link note removed'
}

