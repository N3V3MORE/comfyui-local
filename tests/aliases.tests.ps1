$projectRoot = Split-Path -Parent $PSScriptRoot
$aliasScript = Join-Path $projectRoot 'scripts\sync-model-aliases.ps1'

Test-Case 'manifest maps installed weights to official template filenames' {
    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'model-manifest.json') -Raw | ConvertFrom-Json
    $aliases = @($manifest.aliases)

    Assert-Equal 3 $aliases.Count 'official model alias count'
    Assert-True ($aliases.target -contains 'diffusion_models/z_image_turbo_bf16.safetensors') 'Z-Image official diffusion filename'
    Assert-True ($aliases.target -contains 'diffusion_models/flux-2-klein-4b.safetensors') 'FLUX.2 official distilled filename'
    Assert-True ($aliases.target -contains 'text_encoders/qwen_3_4b.safetensors') 'shared official Qwen filename'
}

Test-Case 'model download finishes by synchronizing official aliases' {
    $downloader = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\download-models.ps1') -Raw
    Assert-True ($downloader -match 'sync-model-aliases\.ps1') 'downloader invokes alias synchronization'
}

Test-Case 'model aliases are zero-copy hardlinks and idempotent' {
    . $aliasScript -LibraryOnly
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("comfyui-local-alias-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path (Join-Path $testRoot 'diffusion_models') | Out-Null
    try {
        $source = Join-Path $testRoot 'diffusion_models\quantized.safetensors'
        [IO.File]::WriteAllText($source, 'original')
        $alias = [pscustomobject]@{
            source = 'diffusion_models/quantized.safetensors'
            target = 'diffusion_models/official.safetensors'
        }

        Assert-Equal 'created' (New-ModelAlias -Alias $alias -ModelsRoot $testRoot) 'first alias sync'
        Assert-Equal 'existing' (New-ModelAlias -Alias $alias -ModelsRoot $testRoot) 'second alias sync'
        [IO.File]::AppendAllText($source, '-updated')
        Assert-Equal 'original-updated' ([IO.File]::ReadAllText((Join-Path $testRoot 'diffusion_models\official.safetensors'))) 'alias shares source content'
    }
    finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
