[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:TestCount = 0
$script:FailureCount = 0

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    $script:TestCount++
    try {
        & $Body
        Write-Host "PASS $Name" -ForegroundColor Green
    }
    catch {
        $script:FailureCount++
        Write-Host "FAIL $Name`n  $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message,
        [double]$Tolerance = 0
    )

    if ($Tolerance -gt 0) {
        if ([math]::Abs([double]$Expected - [double]$Actual) -gt $Tolerance) {
            throw "$Message. Expected $Expected +/- $Tolerance; got $Actual"
        }
        return
    }

    if ($Expected -ne $Actual) {
        throw "$Message. Expected '$Expected'; got '$Actual'"
    }
}

Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tests.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Write-Host "Tests: $script:TestCount; Failures: $script:FailureCount"
if ($script:FailureCount -gt 0) { exit 1 }

