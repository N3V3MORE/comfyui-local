[CmdletBinding()]
param([string]$OutputRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = $root }
$python = Join-Path $root '.venv\Scripts\python.exe'
Assert-Condition (Test-Path -LiteralPath $python) 'Run scripts/setup.ps1 before compiling workflows'

$previousPythonPath = $env:PYTHONPATH
$env:PYTHONPATH = Join-Path $root 'src'
try {
    & $python -m comfy_local compile --root $root --output-root $OutputRoot
    if ($LASTEXITCODE -ne 0) { throw "Workflow compiler exited with code $LASTEXITCODE" }
}
finally {
    $env:PYTHONPATH = $previousPythonPath
}
