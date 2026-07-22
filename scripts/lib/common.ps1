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

function Resolve-ManagedPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Label
    )

    $relative = Assert-SafeRelativePath -Path $RelativePath -Label $Label
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath((Join-Path $rootPath $relative))
    $prefix = "$rootPath$([IO.Path]::DirectorySeparatorChar)"
    Assert-Condition ($candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) "$Label must be contained by its managed root"

    $current = $rootPath
    foreach ($part in ($relative -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            Assert-Condition (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "$Label must not traverse a reparse point: $current"
        }
    }
    return $candidate
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FileId {
    param([Parameter(Mandatory)][string]$Path)

    $output = & fsutil.exe file queryfileid $Path
    Assert-Condition ($LASTEXITCODE -eq 0) "Could not inspect hardlink identity: $Path"
    return ($output -join ' ').Trim()
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

