$projectRoot = Split-Path -Parent $PSScriptRoot
$python = Join-Path $projectRoot '.venv\Scripts\python.exe'

Test-Case 'Python compiler unit tests pass' {
    & $python (Join-Path $projectRoot 'tests\run-python-tests.py') | Out-Null

    Assert-Equal 0 $LASTEXITCODE 'Python compiler unit tests failed'
}
