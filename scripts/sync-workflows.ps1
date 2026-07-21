[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
$sources = Read-Json (Join-Path $root 'workflow-sources.json')
$manifest = Read-Json (Join-Path $root 'model-manifest.json')
$outputRoot = Join-Path $root 'workflows\ui'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

function Copy-JsonObject {
    param($Value)
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json
}

function Write-JsonFile {
    param($Value, [string]$Path, [hashtable]$Replacements = @{})
    $json = $Value | ConvertTo-Json -Depth 100
    foreach ($key in $Replacements.Keys) { $json = $json.Replace($key, $Replacements[$key]) }
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Add-CanvasGroup {
    param($Workflow, $Node)
    $x = [double]$Node.pos[0] - 24
    $y = [double]$Node.pos[1] - 56
    $width = [double]$Node.size[0] + 48
    $height = [double]$Node.size[1] + 80
    $Workflow.groups = @([pscustomobject]@{
        id = 1
        title = 'Canvas - edit width and height here'
        bounding = @($x, $y, $width, $height)
        color = '#3f789e'
        font_size = 22
        flags = [pscustomobject]@{}
    })
}

function Remove-MovingModelMetadata {
    param($Workflow)
    $nodes = @($Workflow.nodes)
    if ($null -ne $Workflow.PSObject.Properties['definitions']) {
        foreach ($subgraph in $Workflow.definitions.subgraphs) { $nodes += @($subgraph.nodes) }
    }
    foreach ($node in $nodes) {
        if ($null -ne $node.PSObject.Properties['properties'] -and
            $null -ne $node.properties.PSObject.Properties['models']) {
            $node.properties.PSObject.Properties.Remove('models')
        }
    }
}

function Set-SdxlWorkflow {
    param($Template, $Model, [string]$OutputName)
    $workflow = Copy-JsonObject $Template
    $loader = $workflow.nodes | Where-Object type -eq 'CheckpointLoaderSimple'
    $latent = $workflow.nodes | Where-Object type -eq 'EmptyLatentImage'
    $sampler = $workflow.nodes | Where-Object type -eq 'KSampler'
    $positive = $workflow.nodes | Where-Object id -eq 6
    $negative = $workflow.nodes | Where-Object id -eq 7
    $save = $workflow.nodes | Where-Object type -eq 'SaveImage'

    $loader.widgets_values[0] = $Model.checkpoint
    $latent.widgets_values = @(1024, 1024, 1)
    $sampler.widgets_values[0] = 246813579
    $sampler.widgets_values[2] = [int]$Model.steps
    $sampler.widgets_values[3] = [double]$Model.cfg
    $sampler.widgets_values[4] = $Model.sampler
    $sampler.widgets_values[5] = $Model.scheduler
    $sampler.widgets_values[6] = 1.0
    $positive.widgets_values[0] = $Model.positivePrompt
    $negative.widgets_values[0] = $Model.negativePrompt
    if ($null -eq $save.PSObject.Properties['widgets_values']) {
        $save | Add-Member -NotePropertyName widgets_values -NotePropertyValue @($OutputName)
    }
    else {
    $save.widgets_values[0] = $OutputName
    }
    Add-CanvasGroup -Workflow $workflow -Node $latent
    Remove-MovingModelMetadata -Workflow $workflow
    return $workflow
}

function Keep-ConnectedSubgraph {
    param($Workflow, [string]$SubgraphId)
    $subgraphNode = $Workflow.nodes | Where-Object type -eq $SubgraphId
    $connectedLinks = @($Workflow.links | Where-Object { $_[1] -eq $subgraphNode.id -or $_[3] -eq $subgraphNode.id })
    $keepIds = @($subgraphNode.id)
    foreach ($link in $connectedLinks) { $keepIds += $link[1]; $keepIds += $link[3] }
    $keepIds = @($keepIds | Select-Object -Unique)
    $Workflow.nodes = @($Workflow.nodes | Where-Object { $_.id -in $keepIds -and $_.type -ne 'MarkdownNote' })
    $Workflow.links = @($Workflow.links | Where-Object { $_[1] -in $keepIds -and $_[3] -in $keepIds })
    Add-CanvasGroup -Workflow $Workflow -Node $subgraphNode
}

$sdxlTemplate = Invoke-RestMethod -Uri $sources.sdxl
$realvis = $manifest.models | Where-Object id -eq 'realvis-xl-v5'
$animagine = $manifest.models | Where-Object id -eq 'animagine-xl-4-opt'
Write-JsonFile (Set-SdxlWorkflow $sdxlTemplate $realvis 'realistic-sdxl') (Join-Path $outputRoot 'realistic-sdxl.json')
Write-JsonFile (Set-SdxlWorkflow $sdxlTemplate $animagine 'anime-sdxl') (Join-Path $outputRoot 'anime-sdxl.json')

$zWorkflow = Invoke-RestMethod -Uri $sources.zImage
$zDefinition = $zWorkflow.definitions.subgraphs | Select-Object -First 1
$zWorkflow.definitions.subgraphs = @($zDefinition)
($zDefinition.nodes | Where-Object type -eq 'UNETLoader').widgets_values[0] = 'z_image_turbo_nvfp4.safetensors'
($zDefinition.nodes | Where-Object type -eq 'CLIPLoader').widgets_values[0] = 'qwen_3_4b_fp4_mixed.safetensors'
($zDefinition.nodes | Where-Object type -eq 'VAELoader').widgets_values[0] = 'ae.safetensors'
($zDefinition.nodes | Where-Object type -eq 'CLIPTextEncode').widgets_values[0] = ($manifest.models | Where-Object id -eq 'z-image-turbo').positivePrompt
($zDefinition.nodes | Where-Object type -eq 'EmptySD3LatentImage').widgets_values = @(1024, 1024, 1)
$zSampler = $zDefinition.nodes | Where-Object type -eq 'KSampler'
$zSampler.widgets_values[0] = 246813579
$zSampler.widgets_values[1] = 'fixed'
$zSampler.widgets_values[2] = 8
Keep-ConnectedSubgraph -Workflow $zWorkflow -SubgraphId $zDefinition.id
Remove-MovingModelMetadata -Workflow $zWorkflow
Write-JsonFile $zWorkflow (Join-Path $outputRoot 'z-image-turbo.json') @{
    'qwen_3_4b.safetensors' = 'qwen_3_4b_fp4_mixed.safetensors'
    'z_image_turbo_bf16.safetensors' = 'z_image_turbo_nvfp4.safetensors'
}

$fluxWorkflow = Invoke-RestMethod -Uri $sources.flux2
$fluxDefinition = $fluxWorkflow.definitions.subgraphs | Where-Object name -match 'Distilled' | Select-Object -First 1
$fluxWorkflow.definitions.subgraphs = @($fluxDefinition)
($fluxDefinition.nodes | Where-Object type -eq 'UNETLoader').widgets_values[0] = 'flux-2-klein-4b-fp8.safetensors'
($fluxDefinition.nodes | Where-Object type -eq 'CLIPLoader').widgets_values[0] = 'qwen_3_4b_fp4_flux2.safetensors'
($fluxDefinition.nodes | Where-Object type -eq 'VAELoader').widgets_values[0] = 'flux2-vae.safetensors'
($fluxDefinition.nodes | Where-Object type -eq 'PrimitiveInt' | Where-Object title -eq 'Width').widgets_values[0] = 1024
($fluxDefinition.nodes | Where-Object type -eq 'PrimitiveInt' | Where-Object title -eq 'Height').widgets_values[0] = 1024
($fluxDefinition.nodes | Where-Object type -eq 'EmptyFlux2LatentImage').widgets_values = @(1024, 1024, 1)
($fluxDefinition.nodes | Where-Object type -eq 'Flux2Scheduler').widgets_values = @(4, 1024, 1024)
($fluxDefinition.nodes | Where-Object type -eq 'RandomNoise').widgets_values = @(246813579, 'fixed')
Keep-ConnectedSubgraph -Workflow $fluxWorkflow -SubgraphId $fluxDefinition.id
($fluxWorkflow.nodes | Where-Object type -eq 'PrimitiveStringMultiline').widgets_values[0] = ($manifest.models | Where-Object id -eq 'flux2-klein-4b').positivePrompt
Remove-MovingModelMetadata -Workflow $fluxWorkflow
Write-JsonFile $fluxWorkflow (Join-Path $outputRoot 'flux2-klein.json') @{
    'qwen_3_4b.safetensors' = 'qwen_3_4b_fp4_flux2.safetensors'
}

Write-Output "Wrote four workflows to $outputRoot"
