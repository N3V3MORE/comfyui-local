[CmdletBinding()]
param([switch]$PrintPlan)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$root = Get-ProjectRoot
$catalog = Read-Json (Join-Path $root 'workflow-catalog.json')
$appsRoot = Join-Path $root 'workflows\apps'
$installedRoot = Join-Path $root 'data\user\default\workflows\ComfyUI Local Studio'
$referenceName = 'studio-reference.webp'

if ($PrintPlan) {
    foreach ($app in $catalog.apps) {
        Write-Output "$($app.id)`t$($app.file.Replace('/', '\'))"
    }
    exit 0
}

function Copy-JsonObject {
    param([Parameter(Mandatory)]$Value)
    return (($Value | ConvertTo-Json -Depth 100) | ConvertFrom-Json)
}

function Set-AppData {
    param(
        [Parameter(Mandatory)]$Workflow,
        [Parameter(Mandatory)][object[]]$Inputs,
        [Parameter(Mandatory)]$OutputId
    )

    if ($null -eq $Workflow.extra) {
        $Workflow | Add-Member -MemberType NoteProperty -Name extra -Value ([pscustomobject]@{})
    }
    $serializedInputs = [Collections.ArrayList]::new()
    foreach ($input in $Inputs) {
        [void]$serializedInputs.Add([object[]]@($input.NodeId, $input.Widget))
    }
    $linearData = [ordered]@{ inputs = $serializedInputs; outputs = @($OutputId) }
    if ($Workflow.extra -is [Collections.IDictionary]) {
        $Workflow.extra['linearMode'] = $true
        $Workflow.extra['linearData'] = $linearData
    }
    else {
        $Workflow.extra | Add-Member -MemberType NoteProperty -Name linearMode -Value $true -Force
        $Workflow.extra | Add-Member -MemberType NoteProperty -Name linearData -Value $linearData -Force
    }
}

function New-AppInput {
    param([Parameter(Mandatory)]$NodeId, [Parameter(Mandatory)][string]$Widget)
    return [pscustomobject]@{ NodeId = $NodeId; Widget = $Widget }
}

function Write-Workflow {
    param([Parameter(Mandatory)][string]$RelativePath, [Parameter(Mandatory)]$Workflow)
    $path = Join-Path $appsRoot $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText(
        $path,
        ($Workflow | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function New-SdxlCreateApp {
    param([Parameter(Mandatory)]$Model, [Parameter(Mandatory)][string]$SourceFile)

    $workflow = Get-Content -LiteralPath (Join-Path $root "workflows\ui\$SourceFile") -Raw | ConvertFrom-Json
    ($workflow.nodes | Where-Object type -eq 'CheckpointLoaderSimple').widgets_values[0] = $Model.checkpoint
    $textNodes = @($workflow.nodes | Where-Object type -eq 'CLIPTextEncode' | Sort-Object id)
    $textNodes[0].widgets_values[0] = $Model.positivePrompt
    $textNodes[1].widgets_values[0] = $Model.negativePrompt
    ($workflow.nodes | Where-Object type -eq 'EmptyLatentImage').widgets_values = @(1024, 1024, 1)
    ($workflow.nodes | Where-Object type -eq 'KSampler').widgets_values = @(
        246813579, 'fixed', $Model.steps, $Model.cfg, $Model.sampler, $Model.scheduler, 1.0
    )
    $save = $workflow.nodes | Where-Object type -eq 'SaveImage'
    $save.widgets_values[0] = $Model.id
    $latent = $workflow.nodes | Where-Object type -eq 'EmptyLatentImage'
    $sampler = $workflow.nodes | Where-Object type -eq 'KSampler'
    Set-AppData $workflow @(
        (New-AppInput $textNodes[0].id 'text')
        (New-AppInput $textNodes[1].id 'text')
        (New-AppInput $latent.id 'width')
        (New-AppInput $latent.id 'height')
        (New-AppInput $sampler.id 'seed')
    ) $save.id
    return $workflow
}

function New-SdxlControlApp {
    param(
        [Parameter(Mandatory)][string]$Preprocessor,
        [Parameter(Mandatory)][object[]]$PreprocessorWidgets,
        [Parameter(Mandatory)][string]$UnionType,
        [Parameter(Mandatory)][string]$Prefix
    )

    $nodes = @(
        [ordered]@{id=1;type='CheckpointLoaderSimple';pos=@(0,300);size=@(315,98);flags=@{};order=0;mode=0;outputs=@(
            @{name='MODEL';type='MODEL';links=@(1);slot_index=0},
            @{name='CLIP';type='CLIP';links=@(2,3);slot_index=1},
            @{name='VAE';type='VAE';links=@(4);slot_index=2}
        );properties=@{};widgets_values=@('realistic\RealVisXL_V5.0_fp16.safetensors')},
        [ordered]@{id=2;type='LoadImage';pos=@(0,0);size=@(315,310);flags=@{};order=1;mode=0;outputs=@(
            @{name='IMAGE';type='IMAGE';links=@(5);slot_index=0},
            @{name='MASK';type='MASK';links=$null;slot_index=1}
        );properties=@{};widgets_values=@($referenceName, 'image')},
        [ordered]@{id=3;type=$Preprocessor;pos=@(350,0);size=@(315,180);flags=@{};order=2;mode=0;inputs=@(
            @{name='image';type='IMAGE';link=5}
        );outputs=@(@{name='IMAGE';type='IMAGE';links=@(6);slot_index=0});properties=@{};widgets_values=$PreprocessorWidgets},
        [ordered]@{id=4;type='ControlNetLoader';pos=@(350,210);size=@(315,58);flags=@{};order=3;mode=0;outputs=@(
            @{name='CONTROL_NET';type='CONTROL_NET';links=@(7);slot_index=0}
        );properties=@{};widgets_values=@('sdxl-controlnet-union-promax.safetensors')},
        [ordered]@{id=5;type='SetUnionControlNetType';pos=@(700,210);size=@(315,82);flags=@{};order=4;mode=0;inputs=@(
            @{name='control_net';type='CONTROL_NET';link=7}
        );outputs=@(@{name='CONTROL_NET';type='CONTROL_NET';links=@(8);slot_index=0});properties=@{};widgets_values=@($UnionType)},
        [ordered]@{id=6;type='CLIPTextEncode';pos=@(350,330);size=@(420,160);flags=@{};order=5;mode=0;inputs=@(
            @{name='clip';type='CLIP';link=2}
        );outputs=@(@{name='CONDITIONING';type='CONDITIONING';links=@(9);slot_index=0});properties=@{};widgets_values=@('A natural cinematic photograph, realistic texture, detailed subject, balanced composition')},
        [ordered]@{id=7;type='CLIPTextEncode';pos=@(350,520);size=@(420,160);flags=@{};order=6;mode=0;inputs=@(
            @{name='clip';type='CLIP';link=3}
        );outputs=@(@{name='CONDITIONING';type='CONDITIONING';links=@(10);slot_index=0});properties=@{};widgets_values=@('bad anatomy, deformed, blurry, plastic skin, text, watermark')},
        [ordered]@{id=8;type='ControlNetApplyAdvanced';pos=@(800,330);size=@(315,190);flags=@{};order=7;mode=0;inputs=@(
            @{name='positive';type='CONDITIONING';link=9},
            @{name='negative';type='CONDITIONING';link=10},
            @{name='control_net';type='CONTROL_NET';link=8},
            @{name='image';type='IMAGE';link=6}
        );outputs=@(
            @{name='positive';type='CONDITIONING';links=@(11);slot_index=0},
            @{name='negative';type='CONDITIONING';links=@(12);slot_index=1}
        );properties=@{};widgets_values=@(0.85,0.0,1.0)},
        [ordered]@{id=9;type='StudioResolutionPreset';pos=@(800,550);size=@(315,58);flags=@{};order=8;mode=0;outputs=@(
            @{name='width';type='INT';links=@(13);slot_index=0},
            @{name='height';type='INT';links=@(14);slot_index=1},
            @{name='label';type='STRING';links=$null;slot_index=2}
        );properties=@{};widgets_values=@('Square 1:1')},
        [ordered]@{id=10;type='EmptyLatentImage';pos=@(800,640);size=@(315,106);flags=@{};order=9;mode=0;inputs=@(
            @{name='width';type='INT';widget=@{name='width'};link=13},
            @{name='height';type='INT';widget=@{name='height'};link=14}
        );outputs=@(@{name='LATENT';type='LATENT';links=@(15);slot_index=0});properties=@{};widgets_values=@(1024,1024,1)},
        [ordered]@{id=11;type='KSampler';pos=@(1150,330);size=@(315,262);flags=@{};order=10;mode=0;inputs=@(
            @{name='model';type='MODEL';link=1},
            @{name='positive';type='CONDITIONING';link=11},
            @{name='negative';type='CONDITIONING';link=12},
            @{name='latent_image';type='LATENT';link=15}
        );outputs=@(@{name='LATENT';type='LATENT';links=@(16);slot_index=0});properties=@{};widgets_values=@(246813579,'fixed',30,5.0,'dpmpp_2m','karras',1.0)},
        [ordered]@{id=12;type='VAEDecode';pos=@(1500,330);size=@(210,46);flags=@{};order=11;mode=0;inputs=@(
            @{name='samples';type='LATENT';link=16},
            @{name='vae';type='VAE';link=4}
        );outputs=@(@{name='IMAGE';type='IMAGE';links=@(17);slot_index=0});properties=@{}},
        [ordered]@{id=13;type='SaveImage';pos=@(1740,330);size=@(315,300);flags=@{};order=12;mode=0;inputs=@(
            @{name='images';type='IMAGE';link=17}
        );outputs=@();properties=@{};widgets_values=@($Prefix)}
    )
    $links = @(
        ,@(1,1,0,11,0,'MODEL'), ,@(2,1,1,6,0,'CLIP'), ,@(3,1,1,7,0,'CLIP'),
        ,@(4,1,2,12,1,'VAE'), ,@(5,2,0,3,0,'IMAGE'), ,@(6,3,0,8,3,'IMAGE'),
        ,@(7,4,0,5,0,'CONTROL_NET'), ,@(8,5,0,8,2,'CONTROL_NET'),
        ,@(9,6,0,8,0,'CONDITIONING'), ,@(10,7,0,8,1,'CONDITIONING'),
        ,@(11,8,0,11,1,'CONDITIONING'), ,@(12,8,1,11,2,'CONDITIONING'),
        ,@(13,9,0,10,0,'INT'), ,@(14,9,1,10,1,'INT'), ,@(15,10,0,11,3,'LATENT'),
        ,@(16,11,0,12,0,'LATENT'), ,@(17,12,0,13,0,'IMAGE')
    )
    $workflow = [pscustomobject][ordered]@{
        last_node_id=13;last_link_id=17;nodes=$nodes;links=$links;groups=@();config=@{};
        extra=[ordered]@{ds=[ordered]@{offset=@(0,0);scale=0.8}};version=0.4
    }
    Set-AppData $workflow @(
        (New-AppInput 2 'image')
        (New-AppInput 6 'text')
        (New-AppInput 7 'text')
        (New-AppInput 9 'preset')
        (New-AppInput 8 'strength')
        (New-AppInput 11 'seed')
    ) 13
    return $workflow
}

function New-UpscaleApp {
    param([Parameter(Mandatory)][string]$ModelName, [Parameter(Mandatory)][string]$Prefix)

    $workflow = [pscustomobject][ordered]@{
        last_node_id=4;last_link_id=3
        nodes=@(
            [ordered]@{id=1;type='LoadImage';pos=@(0,0);size=@(315,310);flags=@{};order=0;mode=0;outputs=@(
                @{name='IMAGE';type='IMAGE';links=@(1);slot_index=0}, @{name='MASK';type='MASK';links=$null;slot_index=1}
            );properties=@{};widgets_values=@($referenceName,'image')},
            [ordered]@{id=2;type='UpscaleModelLoader';pos=@(350,0);size=@(315,58);flags=@{};order=1;mode=0;outputs=@(
                @{name='UPSCALE_MODEL';type='UPSCALE_MODEL';links=@(2);slot_index=0}
            );properties=@{};widgets_values=@($ModelName)},
            [ordered]@{id=3;type='ImageUpscaleWithModel';pos=@(700,0);size=@(315,82);flags=@{};order=2;mode=0;inputs=@(
                @{name='upscale_model';type='UPSCALE_MODEL';link=2}, @{name='image';type='IMAGE';link=1}
            );outputs=@(@{name='IMAGE';type='IMAGE';links=@(3);slot_index=0});properties=@{}},
            [ordered]@{id=4;type='SaveImage';pos=@(1050,0);size=@(315,300);flags=@{};order=3;mode=0;inputs=@(
                @{name='images';type='IMAGE';link=3}
            );outputs=@();properties=@{};widgets_values=@($Prefix)}
        )
        links=@(,@(1,1,0,3,1,'IMAGE'),,@(2,2,0,3,0,'UPSCALE_MODEL'),,@(3,3,0,4,0,'IMAGE'))
        groups=@();config=@{};extra=[ordered]@{ds=[ordered]@{offset=@(0,0);scale=1}};version=0.4
    }
    Set-AppData $workflow @((New-AppInput 1 'image')) 4
    return $workflow
}

$models = (Read-Json (Join-Path $root 'model-manifest.json')).models
$createApps = @(
    @{Id='realvis-xl';File='Create/realvis-xl.app.json';ModelId='realvis-xl-v5';Source='realistic-sdxl.json'},
    @{Id='juggernaut-xl';File='Create/juggernaut-xl.app.json';ModelId='juggernaut-xl-v9';Source='realistic-sdxl.json'},
    @{Id='animagine-xl';File='Create/animagine-xl.app.json';ModelId='animagine-xl-4-opt';Source='anime-sdxl.json'},
    @{Id='illustrious-xl';File='Create/illustrious-xl.app.json';ModelId='illustrious-xl-v2';Source='anime-sdxl.json'}
)
foreach ($entry in $createApps) {
    $model = $models | Where-Object id -eq $entry.ModelId
    Write-Workflow $entry.File (New-SdxlCreateApp $model $entry.Source)
}

$zImage = Get-Content -LiteralPath (Join-Path $root 'workflows\ui\z-image-turbo.json') -Raw | ConvertFrom-Json
$zSubgraphId = $zImage.definitions.subgraphs[0].id
Set-AppData $zImage @(
    (New-AppInput 57 'text')
    (New-AppInput "${zSubgraphId}:13" 'width')
    (New-AppInput "${zSubgraphId}:13" 'height')
    (New-AppInput "${zSubgraphId}:3" 'seed')
) 9
Write-Workflow 'Create/z-image-turbo.app.json' $zImage

$flux = Get-Content -LiteralPath (Join-Path $root 'workflows\ui\flux2-klein.json') -Raw | ConvertFrom-Json
$fluxSubgraphId = $flux.definitions.subgraphs[0].id
Set-AppData $flux @(
    (New-AppInput 76 'value')
    (New-AppInput "${fluxSubgraphId}:68" 'value')
    (New-AppInput "${fluxSubgraphId}:69" 'value')
    (New-AppInput "${fluxSubgraphId}:73" 'noise_seed')
) 78
Write-Workflow 'Create/flux2-klein.app.json' $flux

Write-Workflow 'Control/sdxl-canny.app.json' (New-SdxlControlApp 'CannyEdgePreprocessor' @(100,200,1024) 'canny/lineart/anime_lineart/mlsd' 'sdxl-canny')
Write-Workflow 'Control/sdxl-depth.app.json' (New-SdxlControlApp 'DepthAnythingV2Preprocessor' @('depth_anything_v2_vits.pth',1024) 'depth' 'sdxl-depth')
Write-Workflow 'Control/sdxl-pose.app.json' (New-SdxlControlApp 'DWPreprocessor' @('enable','enable','enable',1024,'yolox_l.torchscript.pt','dw-ll_ucoco_384_bs5.torchscript.pt','disable') 'openpose' 'sdxl-pose')

$zControlSource = Join-Path $root '.venv\Lib\site-packages\comfyui_workflow_templates_json\templates\image_z_image_turbo_fun_union_controlnet.json'
Assert-Condition (Test-Path -LiteralPath $zControlSource) 'Pinned Z-Image control template is missing'
$zControl = Get-Content -LiteralPath $zControlSource -Raw | ConvertFrom-Json
$zControl.nodes = @($zControl.nodes | Where-Object type -ne 'MarkdownNote')
($zControl.nodes | Where-Object type -eq 'LoadImage').widgets_values = @($referenceName, 'image')
$zControlSubgraph = $zControl.definitions.subgraphs[0]
($zControlSubgraph.nodes | Where-Object type -eq 'CLIPLoader').widgets_values[0] = 'qwen_3_4b_fp4_mixed.safetensors'
($zControlSubgraph.nodes | Where-Object type -eq 'UNETLoader').widgets_values[0] = 'z_image_turbo_nvfp4.safetensors'
($zControlSubgraph.nodes | Where-Object type -eq 'ModelPatchLoader').widgets_values[0] = 'Z-Image-Turbo-Fun-Controlnet-Union-2.1-lite-2602-8steps.safetensors'
Set-AppData $zControl @(
    (New-AppInput 58 'image')
    (New-AppInput "$($zControlSubgraph.id):45" 'text')
    (New-AppInput "$($zControlSubgraph.id):44" 'seed')
) 9
Write-Workflow 'Control/z-image-canny.app.json' $zControl

$ipAdapter = Get-Content -LiteralPath (Join-Path $root 'ComfyUI\custom_nodes\ComfyUI_IPAdapter_plus\examples\ipadapter_simple.json') -Raw | ConvertFrom-Json
($ipAdapter.nodes | Where-Object type -eq 'CheckpointLoaderSimple').widgets_values[0] = 'realistic\RealVisXL_V5.0_fp16.safetensors'
($ipAdapter.nodes | Where-Object type -eq 'LoadImage').widgets_values = @($referenceName, 'image')
($ipAdapter.nodes | Where-Object type -eq 'EmptyLatentImage').widgets_values = @(1024,1024,1)
($ipAdapter.nodes | Where-Object type -eq 'KSampler').widgets_values = @(246813579,'fixed',30,5.0,'dpmpp_2m','karras',1.0)
$ipText = @($ipAdapter.nodes | Where-Object type -eq 'CLIPTextEncode' | Sort-Object id)
$ipText[0].widgets_values[0] = 'A natural editorial photograph, detailed subject, realistic light and texture'
$ipText[1].widgets_values[0] = 'bad anatomy, deformed, blurry, plastic skin, text, watermark'
Set-AppData $ipAdapter @(
    (New-AppInput 12 'image')
    (New-AppInput 6 'text')
    (New-AppInput 7 'text')
    (New-AppInput 10 'weight')
    (New-AppInput 5 'width')
    (New-AppInput 5 'height')
    (New-AppInput 3 'seed')
) 9
Write-Workflow 'Reference/sdxl-ipadapter.app.json' $ipAdapter

$face = Get-Content -LiteralPath (Join-Path $root 'ComfyUI\custom_nodes\ComfyUI-Impact-Pack\example_workflows\1-FaceDetailer.json') -Raw | ConvertFrom-Json
$face.nodes = @($face.nodes | Where-Object id -ne 16)
$face.links = @($face.links | Where-Object { $_[0] -ne 151 })
$faceDetailer = $face.nodes | Where-Object type -eq 'FaceDetailer'
($faceDetailer.inputs | Where-Object name -eq 'sam_model_opt').link = $null
($face.nodes | Where-Object type -eq 'UltralyticsDetectorProvider').widgets_values[0] = 'bbox/face_yolov8n.pt'
($face.nodes | Where-Object type -eq 'CheckpointLoaderSimple').widgets_values[0] = 'realistic\RealVisXL_V5.0_fp16.safetensors'
($face.nodes | Where-Object type -eq 'EmptyLatentImage').widgets_values = @(832,1216,1)
($face.nodes | Where-Object type -eq 'KSampler').widgets_values = @(246813579,'fixed',30,5.0,'dpmpp_2m','karras',1.0)
$faceText = @($face.nodes | Where-Object type -eq 'CLIPTextEncode' | Sort-Object id)
$faceText[0].widgets_values[0] = 'Professional portrait photograph, natural skin, detailed eyes, soft studio lighting'
$faceText[1].widgets_values[0] = 'bad anatomy, deformed face, blurry, plastic skin, text, watermark'
Set-AppData $face @(
    (New-AppInput 5 'text')
    (New-AppInput 6 'text')
    (New-AppInput 29 'width')
    (New-AppInput 29 'height')
    (New-AppInput 28 'seed')
    (New-AppInput 51 'denoise')
) 7
Write-Workflow 'Detail/sdxl-face-detail.app.json' $face

Write-Workflow 'Upscale/upscale-photo-2x.app.json' (New-UpscaleApp 'RealESRGAN_x2plus.pth' 'upscale-photo-2x')
Write-Workflow 'Upscale/upscale-photo-4x.app.json' (New-UpscaleApp 'RealESRGAN_x4plus.pth' 'upscale-photo-4x')
Write-Workflow 'Upscale/upscale-anime-4x.app.json' (New-UpscaleApp 'RealESRGAN_x4plus_anime_6B.pth' 'upscale-anime-4x')

$referenceSource = Join-Path $root '.venv\Lib\site-packages\comfyui_workflow_templates_media_image\templates\image_z_image_turbo_fun_union_controlnet-1.webp'
$referenceDestination = Join-Path $root "data\input\$referenceName"
Assert-Condition (Test-Path -LiteralPath $referenceSource) 'Pinned studio reference image is missing'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $referenceDestination) | Out-Null
Copy-Item -LiteralPath $referenceSource -Destination $referenceDestination -Force

foreach ($app in $catalog.apps) {
    $source = Join-Path $appsRoot $app.file.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $destination = Join-Path $installedRoot $app.file.Replace('/', [IO.Path]::DirectorySeparatorChar)
    Assert-Condition (Test-Path -LiteralPath $source) "$($app.id) workflow was not generated"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

Write-Output "Generated and installed $($catalog.apps.Count) App Mode workflows"
