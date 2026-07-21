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
}

Test-Case 'low-VRAM launch adds one explicit flag' {
    $command = ((& $startScript -PrintCommand -LowVram) -join ' ').Trim()
    $matches = [regex]::Matches($command, '(?:^|\s)--lowvram(?:\s|$)')

    Assert-Equal 1 $matches.Count 'low-VRAM flag count'
}

Test-Case 'static verification proves runtime and distinguishes missing models' {
    $output = ((& $verifyScript -StaticOnly -SkipArtifactHashes) -join "`n")

    Assert-True ($output -match 'ComfyUI commit: d0fec2ef7e7086533fde261de3fdb88289bdca9e') 'verification reports exact commit'
    Assert-True ($output -match 'Torch: 2\.11\.0\+cu130') 'verification reports exact Torch'
    Assert-True ($output -match 'CUDA available: True') 'verification reports CUDA'
    Assert-True ($output -match 'GPU: NVIDIA GeForce RTX 5060 Laptop GPU') 'verification reports GPU'
    Assert-True ($output -match 'Artifact records: 10; hash checks skipped') 'routine verification skips expensive model hashes'
    Assert-True ($output -match 'UI workflows: 4 valid') 'verification validates four workflows'
}
