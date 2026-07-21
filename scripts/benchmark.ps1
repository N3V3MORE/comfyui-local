[CmdletBinding()]
param(
    [string[]]$ModelId = @(),
    [string[]]$PresetId = @(),
    [long]$Seed = 20260721,
    [string]$Server = 'http://127.0.0.1:8188',
    [int]$TimeoutMinutes = 20,
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

function Get-ProofMatrix {
    param(
        [Parameter(Mandatory)]$Models,
        [Parameter(Mandatory)]$Presets,
        [Parameter(Mandatory)][string[]]$PresetIds
    )

    foreach ($model in $Models) {
        foreach ($presetId in $PresetIds) {
            $preset = $Presets | Where-Object id -eq $presetId | Select-Object -First 1
            Assert-Condition ($null -ne $preset) "Missing proof preset: $presetId"
            [pscustomobject]@{
                modelId = $model.id
                model = $model
                presetId = $preset.id
                orientation = $preset.orientation
                preset = $preset
            }
        }
    }
}

function Get-PeakVramMiB {
    param([object[]]$Samples = @())

    $values = @($Samples | Where-Object { "$_" -match '^\d+$' } | ForEach-Object { [int]$_ })
    if ($values.Count -eq 0) { return 0 }
    return [int]($values | Measure-Object -Maximum).Maximum
}

function Start-GpuMemoryMonitor {
    return Start-Job -ScriptBlock {
        while ($true) {
            & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            Start-Sleep -Milliseconds 200
        }
    }
}

function Stop-GpuMemoryMonitor {
    param([Parameter(Mandatory)]$Job)

    Stop-Job -Job $Job
    $samples = @(Receive-Job -Job $Job)
    Remove-Job -Job $Job
    return Get-PeakVramMiB -Samples $samples
}

function Submit-ComfyPrompt {
    param([Parameter(Mandatory)]$Workflow, [Parameter(Mandatory)][string]$Server)

    $body = @{ prompt = $Workflow; client_id = "comfyui-local-$([guid]::NewGuid())" } |
        ConvertTo-Json -Depth 50 -Compress
    $response = Invoke-RestMethod -Method Post -Uri "$Server/prompt" -ContentType 'application/json' -Body $body -TimeoutSec 60
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($response.prompt_id)) 'ComfyUI did not return a prompt id'
    return $response.prompt_id
}

function Get-ComfyHistoryEntry {
    param(
        [Parameter(Mandatory)]$History,
        [Parameter(Mandatory)][string]$PromptId
    )

    $property = $History.PSObject.Properties[$PromptId]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ComfyImages {
    param([Parameter(Mandatory)]$Outputs)

    foreach ($output in $Outputs.PSObject.Properties.Value) {
        $imagesProperty = $output.PSObject.Properties['images']
        if ($null -eq $imagesProperty) { continue }
        foreach ($image in @($imagesProperty.Value)) {
            if ($null -ne $image) { Write-Output $image }
        }
    }
}

function Wait-ComfyPrompt {
    param(
        [Parameter(Mandatory)][string]$PromptId,
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][int]$TimeoutMinutes
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        $history = Invoke-RestMethod -Uri "$Server/history/$PromptId" -TimeoutSec 30
        $entry = Get-ComfyHistoryEntry -History $history -PromptId $PromptId
        if ($null -ne $entry) {
            if ($entry.status.status_str -eq 'error') {
                throw "ComfyUI prompt failed: $PromptId"
            }
            if ([bool]$entry.status.completed) {
                $images = @(Get-ComfyImages -Outputs $entry.outputs)
                Assert-Condition ($images.Count -gt 0) "Prompt completed without an image: $PromptId"
                return [pscustomobject]@{ images = $images }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw "ComfyUI prompt timed out after $TimeoutMinutes minutes: $PromptId"
}

function Copy-ComfyImage {
    param(
        [Parameter(Mandatory)]$Image,
        [Parameter(Mandatory)][string]$ComfyOutputRoot,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$ModelId
    )

    $source = Join-Path (Join-Path $ComfyOutputRoot $Image.subfolder) $Image.filename
    Assert-Condition (Test-Path -LiteralPath $source) "ComfyUI output is missing: $source"
    $destinationDirectory = Join-Path $DestinationRoot $ModelId
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    $destination = Join-Path $destinationDirectory $Image.filename
    Copy-Item -LiteralPath $source -Destination $destination -Force
    return $destination
}

if ($LibraryOnly) { return }

$root = Get-ProjectRoot
$modelConfig = Read-Json (Join-Path $root 'config\models.json')
$scenarios = Read-Json (Join-Path $root 'config\benchmark-scenarios.json')
$presets = (Read-Json (Join-Path $root 'config\resolutions.json')).resolutions
$models = @($modelConfig.models)
if ($ModelId.Count -gt 0) {
    $models = @($models | Where-Object { $ModelId -contains $_.id })
    Assert-Condition ($models.Count -eq $ModelId.Count) 'One or more requested model ids are unknown'
}
$selectedPresetIds = if ($PresetId.Count -gt 0) { $PresetId } else { @($scenarios.orientationProof.presetIds) }
$selectedPresets = @($presets | Where-Object { $selectedPresetIds -contains $_.id })
Assert-Condition ($selectedPresets.Count -eq $selectedPresetIds.Count) 'One or more requested preset ids are unknown'

Invoke-RestMethod -Uri "$Server/system_stats" -TimeoutSec 10 | Out-Null
$proofRoot = Join-Path $root 'results\proof'
$promptRoot = Join-Path $root 'results\prompts'
$python = Join-Path $root '.venv\Scripts\python.exe'
Assert-Condition (Test-Path -LiteralPath $python) 'Python environment is missing'
$env:PYTHONPATH = Join-Path $root 'src'
$rows = [Collections.Generic.List[object]]::new()

foreach ($model in $models) {
    foreach ($canvas in $selectedPresets) {
        $prefix = "proof/$($model.id)/$($model.id)-$($canvas.id)"
        $promptPath = Join-Path $promptRoot "$($model.id)-$($canvas.id).json"
        & $python -m comfy_local prompt --root $root --model-id $model.id --width $canvas.width --height $canvas.height --seed $Seed --filename-prefix $prefix --output $promptPath
        Assert-Condition ($LASTEXITCODE -eq 0) "Prompt materialization failed: $($model.id) at $($canvas.id)"
        $workflow = Read-Json $promptPath

        Write-Output "Generating $($model.id) at $($canvas.id)..."
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $vramMonitor = Start-GpuMemoryMonitor
        try {
            $promptId = Submit-ComfyPrompt -Workflow $workflow -Server $Server
            $completed = Wait-ComfyPrompt -PromptId $promptId -Server $Server -TimeoutMinutes $TimeoutMinutes
        }
        finally {
            $watch.Stop()
            $peakVramMiB = Stop-GpuMemoryMonitor -Job $vramMonitor
        }
        $copied = @(foreach ($image in $completed.images) {
            Copy-ComfyImage -Image $image -ComfyOutputRoot (Join-Path $root 'ComfyUI\output') -DestinationRoot $proofRoot -ModelId $model.id
        })

        $rows.Add([pscustomobject][ordered]@{
            modelId = $model.id
            name = $model.name
            category = $model.category
            family = $model.family
            precision = $model.precision
            preset = $canvas.id
            orientation = $canvas.orientation
            width = $canvas.width
            height = $canvas.height
            steps = $model.sampling.steps
            seconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
            peakVramMiB = $peakVramMiB
            output = ($copied -join ';')
        })
    }
}

$resultsRoot = Join-Path $root 'results'
New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$rows | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $resultsRoot 'benchmark.json') -Encoding utf8
$rows | Export-Csv -LiteralPath (Join-Path $resultsRoot 'benchmark.csv') -NoTypeInformation -Encoding utf8
Write-Output "Completed $($rows.Count) benchmark images. Results: $resultsRoot"
