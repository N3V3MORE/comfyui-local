Set-StrictMode -Version Latest

function Get-ProjectRoot {
    return Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Read-Json {
    param([Parameter(Mandatory)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-Condition {
    param([bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-SafeRelativePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $normalized = $Path.Replace('/', [IO.Path]::DirectorySeparatorChar)
    Assert-Condition (-not [IO.Path]::IsPathRooted($normalized)) "$Label must be a safe relative path"
    $parts = @($normalized -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Condition ($parts.Count -gt 0 -and $parts -notcontains '..') "$Label must be a safe relative path"
    return $normalized
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

