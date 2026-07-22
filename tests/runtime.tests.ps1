$projectRoot = Split-Path -Parent $PSScriptRoot
$startScript = Join-Path $projectRoot 'scripts\start.ps1'
$verifyScript = Join-Path $projectRoot 'scripts\verify.ps1'

Test-Case 'start command is loopback-only and uses the isolated environment' {
    $command = ((& $startScript -PrintCommand) -join ' ').Trim()

    Assert-True ($command -match '\.venv\\Scripts\\python\.exe') 'launch uses isolated Python'
    Assert-True ($command -match 'ComfyUI\\main\.py') 'launch uses pinned ComfyUI checkout'
    Assert-True ($command -match '--listen 127\.0\.0\.1') 'launch listens only on loopback'
    Assert-True ($command -match '--port 8188') 'launch uses port 8188'
    Assert-True ($command -notmatch '--lowvram') 'default launch does not force low VRAM'
    Assert-True ($command -notmatch '--enable-manager') 'default launch does not enable mutable Manager actions'
}

Test-Case 'Manager is an explicit opt-in launch feature' {
    $command = ((& $startScript -PrintCommand -EnableManager) -join ' ').Trim()

    Assert-True ($command -match '--enable-manager') 'explicit Manager launch adds the Manager flag'
}

Test-Case 'low-VRAM launch adds one explicit flag' {
    $command = ((& $startScript -PrintCommand -LowVram) -join ' ').Trim()
    $matches = [regex]::Matches($command, '(?:^|\s)--lowvram(?:\s|$)')

    Assert-Equal 1 $matches.Count 'low-VRAM flag count'
}

Test-Case 'start exposes the shared resolution configuration to custom nodes' {
    $output = @(& $startScript -PrintEnvironment)

    Assert-True ($output -contains "COMFYUI_LOCAL_CONFIG=$projectRoot\config\resolutions.json") 'start points custom nodes at the shared resolution JSON'
}

Test-Case 'static verification proves runtime and distinguishes missing models' {
    $output = ((& $verifyScript -StaticOnly -SkipArtifactHashes -RequireExtensions) -join "`n")

    Assert-True ($output -match 'ComfyUI commit: d0fec2ef7e7086533fde261de3fdb88289bdca9e') 'verification reports exact commit'
    Assert-True ($output -match 'Torch: 2\.11\.0\+cu130') 'verification reports exact Torch'
    Assert-True ($output -match 'CUDA available: True') 'verification reports CUDA'
    Assert-True ($output -match 'GPU: NVIDIA GeForce RTX 5060 Laptop GPU') 'verification reports GPU'
    Assert-True ($output -match 'Artifact records: 10; hash checks skipped') 'routine verification skips expensive model hashes'
    Assert-True ($output -match 'Support artifact records: 11; hash checks skipped') 'routine verification reports support artifacts'
    Assert-True ($output -match 'UI workflows: 4 valid') 'verification validates four workflows'
    Assert-True ($output -match 'Studio apps: 15 valid') 'verification validates fifteen apps'
    Assert-True ($output -match 'Extensions: 5 pinned') 'verification validates extension pins'
}

Test-Case 'live verification retries a transient Studio workflow listing' {
    $source = Get-Content -LiteralPath $verifyScript -Raw

    Assert-True ($source -match '\$workflowListAttempts\s*=\s*3') 'live verification defines three bounded workflow-list attempts'
    Assert-True ($source -match 'Start-Sleep -Seconds 1') 'live verification briefly waits between attempts'
}

Test-Case 'live verification flattens the Invoke-RestMethod array response' {
    $source = Get-Content -LiteralPath $verifyScript -Raw

    Assert-True ($source -match '\$workflowResponse\s*=\s*Invoke-RestMethod') 'workflow response is captured before array normalization'
    Assert-True ($source -match '\$served\s*=\s*@\(\$workflowResponse\)') 'workflow response is flattened from a variable expression'
    Assert-True ($source -notmatch '\$served\s*=\s*@\(Invoke-RestMethod') 'Invoke-RestMethod is not directly wrapped as a nested array'
}
