[CmdletBinding()]
param(
    [string[]]$ModelId = @(),
    [string[]]$PresetId = @(),
    [ValidateSet('orientation', 'performance', 'quality')]
    [string]$Suite = 'orientation',
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

function Get-Median {
    param([Parameter(Mandatory)][double[]]$Values)

    Assert-Condition ($Values.Count -gt 0) 'Median requires at least one value'
    $sorted = @($Values | Sort-Object)
    $middle = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2
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

function Get-ComfyHistory {
    param(
        [Parameter(Mandatory)][string]$PromptId,
        [Parameter(Mandatory)][string]$Server,
        [int]$Attempts = 3,
        [scriptblock]$Request = { param($Uri) Invoke-RestMethod -Uri $Uri -TimeoutSec 30 }
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return & $Request "$Server/history/$PromptId"
        }
        catch {
            if ($attempt -eq $Attempts) {
                throw "ComfyUI history request failed after $Attempts attempts for ${PromptId}: $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }
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
        [Parameter(Mandatory)][int]$TimeoutMinutes,
        [scriptblock]$HistoryRequest = { param($Uri) Invoke-RestMethod -Uri $Uri -TimeoutSec 30 }
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $lastHistoryError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $history = Get-ComfyHistory -PromptId $PromptId -Server $Server -Request $HistoryRequest
        }
        catch {
            $lastHistoryError = $_.Exception.Message
            Start-Sleep -Milliseconds 500
            continue
        }
        $entry = Get-ComfyHistoryEntry -History $history -PromptId $PromptId
        if ($null -ne $entry) {
            $status = $entry.status
            if ($null -ne $status.PSObject.Properties['status_str'] -and $status.status_str -eq 'error') {
                $messages = $status.messages | ConvertTo-Json -Depth 10 -Compress
                throw "ComfyUI prompt failed: $PromptId; details: $messages"
            }
            if ($null -ne $status.PSObject.Properties['completed'] -and [bool]$status.completed) {
                $images = @(Get-ComfyImages -Outputs $entry.outputs)
                Assert-Condition ($images.Count -gt 0) "Prompt completed without an image: $PromptId"
                return [pscustomobject]@{ images = $images }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    $detail = if ($null -eq $lastHistoryError) { '' } else { "; last history error: $lastHistoryError" }
    throw "ComfyUI prompt timed out after $TimeoutMinutes minutes: $PromptId$detail"
}

function Copy-ComfyImage {
    param(
        [Parameter(Mandatory)]$Image,
        [Parameter(Mandatory)][string]$ComfyOutputRoot,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][string]$ModelId
    )

    $rawSubfolder = [string]$Image.subfolder
    $subfolder = if ([string]::IsNullOrWhiteSpace($rawSubfolder)) { '.' } else {
        Assert-SafeRelativePath -Path $rawSubfolder -Label 'Comfy image subfolder'
    }
    $filename = [string]$Image.filename
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($filename) -and [IO.Path]::GetFileName($filename) -eq $filename) 'Comfy image filename must be a file name'
    $source = Resolve-ManagedPath -Root $ComfyOutputRoot -RelativePath (Join-Path $subfolder $filename) -Label 'Comfy image path'
    Assert-Condition (Test-Path -LiteralPath $source) "ComfyUI output is missing: $source"
    $destination = Resolve-ManagedPath -Root $DestinationRoot -RelativePath (Join-Path $ModelId $filename) -Label 'Benchmark destination path'
    $destinationDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
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
Assert-Condition ($Suite -eq 'orientation' -or $PresetId.Count -eq 0) '-PresetId is only valid for the orientation suite'

Invoke-RestMethod -Uri "$Server/system_stats" -TimeoutSec 10 | Out-Null
$resultsRoot = Join-Path $root 'results'
$proofRoot = Join-Path $resultsRoot "proof\$Suite"
$promptRoot = Join-Path $resultsRoot 'prompts'
$python = Join-Path $root '.venv\Scripts\python.exe'
Assert-Condition (Test-Path -LiteralPath $python) 'Python environment is missing'
$env:PYTHONPATH = Join-Path $root 'src'
$rows = [Collections.Generic.List[object]]::new()

$jobs = if ($Suite -eq 'orientation') {
    $selectedIds = if ($PresetId.Count -gt 0) { $PresetId } else { @($scenarios.orientationProof.presetIds) }
    $selectedPresets = @($presets | Where-Object { $selectedIds -contains $_.id })
    Assert-Condition ($selectedPresets.Count -eq $selectedIds.Count) 'One or more requested preset ids are unknown'
    @(
        foreach ($model in $models) {
            foreach ($canvas in $selectedPresets) {
                [pscustomobject]@{
                    suite = 'orientation'
                    scenario_id = 'orientation-proof'
                    model_id = $model.id
                    width = $canvas.width
                    height = $canvas.height
                    seed = $Seed
                    run_kind = 'orientation'
                    filename_prefix = "proof/$($model.id)/$($model.id)-$($canvas.id)"
                    preset_id = $canvas.id
                    orientation = $canvas.orientation
                }
            }
        }
    )
}
else {
    $planPath = Join-Path $resultsRoot "benchmark-plan-$Suite.json"
    & $python -m comfy_local benchmark-plan --root $root --suite $Suite --output $planPath
    Assert-Condition ($LASTEXITCODE -eq 0) "$Suite benchmark planning failed"
    @(@(Read-Json $planPath) | Where-Object { $_.model_id -in $models.id })
}

foreach ($job in $jobs) {
    $model = $models | Where-Object id -eq $job.model_id | Select-Object -First 1
    Assert-Condition ($null -ne $model) "Unknown planned model: $($job.model_id)"
    $promptName = "$($job.suite)-$($job.scenario_id)-$($job.model_id)-$($job.seed).json"
    $promptPath = Join-Path $promptRoot $promptName
    if ($Suite -eq 'orientation') {
        & $python -m comfy_local prompt --root $root --model-id $job.model_id --width $job.width --height $job.height --seed $job.seed --filename-prefix $job.filename_prefix --output $promptPath
    }
    else {
        & $python -m comfy_local scenario-prompt --root $root --suite $Suite --scenario-id $job.scenario_id --model-id $job.model_id --seed $job.seed --output $promptPath
    }
    Assert-Condition ($LASTEXITCODE -eq 0) "Prompt materialization failed: $($job.model_id)/$($job.scenario_id)"
    $workflow = Read-Json $promptPath

    if ($job.run_kind -eq 'cold') {
        $body = @{ unload_models = $true; free_memory = $true } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post -Uri "$Server/free" -ContentType 'application/json' -Body $body -TimeoutSec 60 | Out-Null
    }

    Write-Output "Generating $($job.model_id) for $($job.scenario_id) ($($job.run_kind))..."
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
        Copy-ComfyImage -Image $image -ComfyOutputRoot (Join-Path $root 'results\images') -DestinationRoot $proofRoot -ModelId $model.id
    })

    $blindSampleId = $blindImage = $null
    if ($Suite -eq 'quality' -and $copied.Count -gt 0) {
        $blindSampleId = 'sample-{0:D4}' -f ($rows.Count + 1)
        $blindRoot = Join-Path $resultsRoot 'quality-blind'
        New-Item -ItemType Directory -Force -Path $blindRoot | Out-Null
        $blindImage = Join-Path $blindRoot ($blindSampleId + [IO.Path]::GetExtension($copied[0]))
        Copy-Item -LiteralPath $copied[0] -Destination $blindImage -Force
    }

    $rows.Add([pscustomobject][ordered]@{
        suite = $Suite
        scenarioId = $job.scenario_id
        runKind = $job.run_kind
        seed = $job.seed
        modelId = $model.id
        name = $model.name
        category = $model.category
        family = $model.family
        precision = $model.precision
        preset = if ($Suite -eq 'orientation') { $job.preset_id } else { $null }
        orientation = if ($Suite -eq 'orientation') { $job.orientation } else { $null }
        width = $job.width
        height = $job.height
        steps = $model.sampling.steps
        seconds = [math]::Round($watch.Elapsed.TotalSeconds, 2)
        peakVramMiB = $peakVramMiB
        output = ($copied -join ';')
        blindSampleId = $blindSampleId
        blindImage = $blindImage
    })
}

New-Item -ItemType Directory -Force -Path $resultsRoot | Out-Null
$rows | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $resultsRoot 'benchmark.json') -Encoding utf8
$rows | Export-Csv -LiteralPath (Join-Path $resultsRoot 'benchmark.csv') -NoTypeInformation -Encoding utf8
$summary = @(
    $rows | Group-Object suite, scenarioId, modelId, runKind | ForEach-Object {
        [pscustomobject][ordered]@{
            suite = $_.Group[0].suite
            scenarioId = $_.Group[0].scenarioId
            modelId = $_.Group[0].modelId
            runKind = $_.Group[0].runKind
            runs = $_.Count
            medianSeconds = [math]::Round((Get-Median -Values @($_.Group.seconds)), 2)
            peakVramMiB = [int]($_.Group.peakVramMiB | Measure-Object -Maximum).Maximum
        }
    }
)
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $resultsRoot 'benchmark-summary.generated.json') -Encoding utf8
if ($Suite -eq 'quality') {
    $rows | Select-Object blindSampleId, scenarioId, blindImage,
        @{Name='composition';Expression={''}}, @{Name='handsFaces';Expression={''}},
        @{Name='embeddedText';Expression={''}}, @{Name='promptAdherence';Expression={''}},
        @{Name='overall';Expression={''}}, @{Name='notes';Expression={''}} |
        Export-Csv -LiteralPath (Join-Path $resultsRoot 'quality-ratings.csv') -NoTypeInformation -Encoding utf8
}
Write-Output "Completed $($rows.Count) benchmark images. Results: $resultsRoot"
