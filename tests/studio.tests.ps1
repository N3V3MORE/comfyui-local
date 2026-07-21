$projectRoot = Split-Path -Parent $PSScriptRoot
$startScript = Join-Path $projectRoot 'scripts\start.ps1'

Test-Case 'pins the five curated ComfyUI extensions' {
    $path = Join-Path $projectRoot 'extensions-manifest.json'
    Assert-True (Test-Path -LiteralPath $path) 'extension manifest must exist'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    $expected = [ordered]@{
        'rgthree-comfy' = '27b4f4cdcf3b127c29d5d8135ac1536ecbd4c383'
        'comfyui-impact-pack' = '429d0159ad429e64d2b3916e6e7be9c22d025c3c'
        'comfyui-impact-subpack' = '50c7b71a6a224734cc9b21963c6d1926816a97f1'
        'comfyui-controlnet-aux' = 'e8b689a513c3e6b63edc44066560ca5919c0576e'
        'comfyui-ipadapter-plus' = 'a0f451a5113cf9becb0847b92884cb10cbdec0ef'
    }

    Assert-Equal 1 $manifest.version 'extension manifest version'
    Assert-Equal $expected.Count $manifest.extensions.Count 'extension count'
    foreach ($id in $expected.Keys) {
        $extension = $manifest.extensions | Where-Object id -eq $id
        Assert-True ($null -ne $extension) "$id must be present"
        Assert-Equal $expected[$id] $extension.commit "$id commit"
        Assert-True ($extension.repository -match '^https://github\.com/.+\.git$') "$id repository must be explicit"
        Assert-True ($extension.commit -match '^[0-9a-f]{40}$') "$id commit must be immutable"
        Assert-True (-not [string]::IsNullOrWhiteSpace($extension.license)) "$id license is required"
        Assert-True (@($extension.requiredNodeTypes).Count -gt 0) "$id must declare required nodes"
    }
}

Test-Case 'defines eleven immutable support assets' {
    $path = Join-Path $projectRoot 'support-model-manifest.json'
    Assert-True (Test-Path -LiteralPath $path) 'support model manifest must exist'
    $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    Assert-Equal 1 $manifest.version 'support manifest version'
    Assert-Equal 11 $manifest.artifacts.Count 'support artifact count'
    Assert-Equal 8516107587 (($manifest.artifacts | Measure-Object -Property bytes -Sum).Sum) 'support payload bytes'
    Assert-Equal 11 @($manifest.artifacts.id | Select-Object -Unique).Count 'support artifact ids must be unique'

    foreach ($artifact in $manifest.artifacts) {
        $immutable = $artifact.url -match '/resolve/[0-9a-f]{40}/' -or
            $artifact.url -match '/releases/download/v[0-9]'
        Assert-True $immutable "$($artifact.id) URL must be immutable"
        Assert-True ($artifact.sha256 -match '^[0-9a-f]{64}$') "$($artifact.id) must have a SHA-256"
        Assert-True ([long]$artifact.bytes -gt 0) "$($artifact.id) must have a positive byte size"
        Assert-True (-not [IO.Path]::IsPathRooted($artifact.target)) "$($artifact.id) target must be relative"
        Assert-True (-not [string]::IsNullOrWhiteSpace($artifact.license)) "$($artifact.id) license is required"
        Assert-True (-not [string]::IsNullOrWhiteSpace($artifact.family)) "$($artifact.id) family is required"
    }
}

Test-Case 'start uses explicit studio paths and enables Manager' {
    $command = ((& $startScript -PrintCommand) -join ' ').Trim()

    Assert-True ($command -match '--models-directory .+models') 'launch sets models directory'
    Assert-True ($command -match '--user-directory .+data\\user') 'launch sets user directory'
    Assert-True ($command -match '--input-directory .+data\\input') 'launch sets input directory'
    Assert-True ($command -match '--temp-directory .+data\\temp') 'launch sets temp directory'
    Assert-True ($command -match '--output-directory .+results\\images') 'launch sets output directory'
    Assert-True ($command -match '--enable-manager') 'launch enables Manager'
}

Test-Case 'core-only launch disables third-party nodes once' {
    $command = ((& $startScript -PrintCommand -CoreOnly) -join ' ').Trim()
    $matches = [regex]::Matches($command, '(?:^|\s)--disable-all-custom-nodes(?:\s|$)')

    Assert-Equal 1 $matches.Count 'core-only flag count'
}

Test-Case 'download and verification scripts include support assets' {
    $downloadSource = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\download-models.ps1') -Raw
    $verifySource = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\verify.ps1') -Raw

    Assert-True ($downloadSource -match 'support-model-manifest\.json') 'downloader reads support assets'
    Assert-True ($verifySource -match 'support-model-manifest\.json') 'verification reads support assets'
    Assert-True ($verifySource -match 'extensions-manifest\.json') 'verification reads extension pins'
}

Test-Case 'studio helper API guards model families and exposes exact presets' {
    $python = Join-Path $projectRoot '.venv\Scripts\python.exe'
    $testFile = Join-Path $projectRoot 'tests\studio_nodes_test.py'
    Assert-True (Test-Path -LiteralPath $testFile) 'studio node Python test must exist'

    & $python $testFile 2>$null | Out-Null
    Assert-Equal 0 $LASTEXITCODE 'studio node Python tests failed'
}
