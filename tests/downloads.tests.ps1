$projectRoot = Split-Path -Parent $PSScriptRoot
$downloadScript = Join-Path $projectRoot 'scripts\download-models.ps1'
. $downloadScript -LibraryOnly

Test-Case 'artifact verification checks size and SHA-256' {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("comfyui-local-download-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    try {
        $fixture = Join-Path $testRoot 'fixture.bin'
        [IO.File]::WriteAllBytes($fixture, [byte[]](0..127))
        $hash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()

        Assert-True (Test-Artifact -Path $fixture -Bytes 128 -Sha256 $hash) 'valid artifact must pass'
        Assert-True (-not (Test-Artifact -Path $fixture -Bytes 127 -Sha256 $hash)) 'wrong size must fail'
        Assert-True (-not (Test-Artifact -Path $fixture -Bytes 128 -Sha256 ('0' * 64))) 'wrong hash must fail'
    }
    finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Test-Case 'artifact installation finalizes only a verified partial file' {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("comfyui-local-install-test-" + [guid]::NewGuid())
    $modelsRoot = Join-Path $testRoot 'models'
    New-Item -ItemType Directory -Path $modelsRoot -Force | Out-Null
    try {
        $source = Join-Path $testRoot 'source.bin'
        [IO.File]::WriteAllBytes($source, [byte[]](255..128))
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        $artifact = [pscustomobject]@{
            id = 'fixture'
            url = ([uri]$source).AbsoluteUri
            target = 'checkpoints/fixture.bin'
            bytes = 128
            sha256 = $hash
        }

        Assert-Equal 'installed' (Install-Artifact -Artifact $artifact -ModelsRoot $modelsRoot) 'first install result'
        $destination = Join-Path $modelsRoot 'checkpoints\fixture.bin'
        Assert-True (Test-Artifact -Path $destination -Bytes 128 -Sha256 $hash) 'installed artifact is valid'
        Assert-Equal 'skipped' (Install-Artifact -Artifact $artifact -ModelsRoot $modelsRoot) 'valid artifact skip result'
    }
    finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Test-Case 'artifact installation rejects a bad digest without a final file' {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("comfyui-local-reject-test-" + [guid]::NewGuid())
    $modelsRoot = Join-Path $testRoot 'models'
    New-Item -ItemType Directory -Path $modelsRoot -Force | Out-Null
    try {
        $source = Join-Path $testRoot 'source.bin'
        [IO.File]::WriteAllBytes($source, [byte[]](0..31))
        $artifact = [pscustomobject]@{
            id = 'bad-fixture'
            url = ([uri]$source).AbsoluteUri
            target = 'checkpoints/bad.bin'
            bytes = 32
            sha256 = ('0' * 64)
        }

        $failed = $false
        try { Install-Artifact -Artifact $artifact -ModelsRoot $modelsRoot | Out-Null }
        catch { $failed = $_.Exception.Message -match 'Integrity check failed' }

        Assert-True $failed 'bad digest must raise an integrity error'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $modelsRoot 'checkpoints\bad.bin'))) 'bad artifact must not be finalized'
    }
    finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

