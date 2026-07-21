[CmdletBinding()]
param(
    [string[]]$ModelId = @(),
    [string[]]$PresetId = @('1024x1024', '1216x832', '832x1216'),
    [long]$Seed = 20260721,
    [string]$Server = 'http://127.0.0.1:8188',
    [int]$TimeoutMinutes = 20,
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

function Set-BenchmarkInputs {
    param(
        [Parameter(Mandatory)]$Workflow,
        [Parameter(Mandatory)]$Model,
        [Parameter(Mandatory)]$Canvas,
        [Parameter(Mandatory)][long]$Seed,
        [Parameter(Mandatory)][string]$FilenamePrefix
    )

    switch ($Model.workflowProfile) {
        'sdxl' {
            $Workflow.'1'.inputs.ckpt_name = $Model.checkpoint
            $Workflow.'2'.inputs.text = $Model.positivePrompt
            $Workflow.'3'.inputs.text = $Model.negativePrompt
            $Workflow.'4'.inputs.width = $Canvas.width
            $Workflow.'4'.inputs.height = $Canvas.height
            $Workflow.'5'.inputs.seed = $Seed
            $Workflow.'5'.inputs.steps = $Model.steps
            $Workflow.'5'.inputs.cfg = $Model.cfg
            $Workflow.'5'.inputs.sampler_name = $Model.sampler
            $Workflow.'5'.inputs.scheduler = $Model.scheduler
            $Workflow.'7'.inputs.filename_prefix = $FilenamePrefix
        }
        'z_image' {
            $Workflow.'1'.inputs.unet_name = $Model.diffusionModel
            $Workflow.'2'.inputs.clip_name = $Model.textEncoder
            $Workflow.'3'.inputs.vae_name = $Model.vae
            $Workflow.'4'.inputs.text = $Model.positivePrompt
            $Workflow.'7'.inputs.width = $Canvas.width
            $Workflow.'7'.inputs.height = $Canvas.height
            $Workflow.'8'.inputs.seed = $Seed
            $Workflow.'8'.inputs.steps = $Model.steps
            $Workflow.'8'.inputs.cfg = $Model.cfg
            $Workflow.'8'.inputs.sampler_name = $Model.sampler
            $Workflow.'8'.inputs.scheduler = $Model.scheduler
            $Workflow.'10'.inputs.filename_prefix = $FilenamePrefix
        }
        'flux2' {
            $Workflow.'1'.inputs.unet_name = $Model.diffusionModel
            $Workflow.'2'.inputs.clip_name = $Model.textEncoder
            $Workflow.'3'.inputs.vae_name = $Model.vae
            $Workflow.'4'.inputs.text = $Model.positivePrompt
            $Workflow.'6'.inputs.cfg = $Model.cfg
            $Workflow.'7'.inputs.noise_seed = $Seed
            $Workflow.'8'.inputs.sampler_name = $Model.sampler
            $Workflow.'9'.inputs.steps = $Model.steps
            $Workflow.'9'.inputs.width = $Canvas.width
            $Workflow.'9'.inputs.height = $Canvas.height
            $Workflow.'10'.inputs.width = $Canvas.width
            $Workflow.'10'.inputs.height = $Canvas.height
            $Workflow.'13'.inputs.filename_prefix = $FilenamePrefix
        }
        default { throw "Unknown workflow profile: $($Model.workflowProfile)" }
    }

}

function Get-ProofMatrix {
    param(
        [Parameter(Mandatory)]$Models,
        [Parameter(Mandatory)]$Presets
    )

    $proofPresetIds = @('1024x1024', '1216x832', '832x1216')
    foreach ($model in $Models) {
        foreach ($presetId in $proofPresetIds) {
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
$manifest = Read-Json (Join-Path $root 'model-manifest.json')
$presets = (Read-Json (Join-Path $root 'config\resolutions.json')).resolutions
$models = @($manifest.models)
if ($ModelId.Count -gt 0) {
    $models = @($models | Where-Object { $ModelId -contains $_.id })
    Assert-Condition ($models.Count -eq $ModelId.Count) 'One or more requested model ids are unknown'
}
$selectedPresets = @($presets | Where-Object { $PresetId -contains $_.id })
Assert-Condition ($selectedPresets.Count -eq $PresetId.Count) 'One or more requested preset ids are unknown'

Invoke-RestMethod -Uri "$Server/system_stats" -TimeoutSec 10 | Out-Null
$proofRoot = Join-Path $root 'results\proof'
$rows = [Collections.Generic.List[object]]::new()

foreach ($model in $models) {
    foreach ($canvas in $selectedPresets) {
        $fixturePath = Join-Path $root "workflows\api\$($model.workflowProfile).json"
        $workflow = Read-Json $fixturePath
        $prefix = "proof/$($model.id)/$($model.id)-$($canvas.id)"
        Set-BenchmarkInputs -Workflow $workflow -Model $model -Canvas $canvas -Seed $Seed -FilenamePrefix $prefix | Out-Null

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
            steps = $model.steps
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
