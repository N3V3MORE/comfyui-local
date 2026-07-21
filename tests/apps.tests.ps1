$projectRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $projectRoot 'workflow-catalog.json'
$appsRoot = Join-Path $projectRoot 'workflows\apps'
$syncScript = Join-Path $projectRoot 'scripts\sync-studio-apps.ps1'

$expectedIds = @(
    'realvis-xl',
    'juggernaut-xl',
    'animagine-xl',
    'illustrious-xl',
    'z-image-turbo',
    'flux2-klein',
    'sdxl-canny',
    'sdxl-depth',
    'sdxl-pose',
    'z-image-canny',
    'sdxl-ipadapter',
    'sdxl-face-detail',
    'upscale-photo-2x',
    'upscale-photo-4x',
    'upscale-anime-4x'
)

Test-Case 'studio catalog defines fifteen focused apps' {
    Assert-True (Test-Path -LiteralPath $catalogPath) 'workflow catalog exists'
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json

    Assert-Equal 1 $catalog.version 'workflow catalog version'
    Assert-Equal 15 $catalog.apps.Count 'studio app count'
    Assert-Equal 15 @($catalog.apps.id | Select-Object -Unique).Count 'studio app ids are unique'
    foreach ($id in $expectedIds) {
        Assert-True ($id -in $catalog.apps.id) "catalog contains $id"
    }
}

Test-Case 'studio workflows are App Mode defaults with declared inputs and outputs' {
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json

    foreach ($app in $catalog.apps) {
        $path = Join-Path $appsRoot $app.file
        Assert-True (Test-Path -LiteralPath $path) "$($app.id) workflow exists"
        $workflow = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $nodeIds = @($workflow.nodes.id | ForEach-Object { [string]$_ })

        Assert-Equal 0.4 $workflow.version "$($app.id) workflow version"
        Assert-Equal $true $workflow.extra.linearMode "$($app.id) opens in App Mode"
        Assert-True (@($workflow.extra.linearData.inputs).Count -ge 1) "$($app.id) has an app input"
        foreach ($input in @($workflow.extra.linearData.inputs)) {
            Assert-True ($input -is [array]) "$($app.id) input is a tuple"
            Assert-Equal 2 @($input).Count "$($app.id) input tuple width"
            Assert-True ($input[0] -isnot [array]) "$($app.id) input node id is not nested"
            Assert-True (-not [string]::IsNullOrWhiteSpace([string]$input[1])) "$($app.id) input widget name"
        }
        Assert-Equal 1 @($workflow.extra.linearData.outputs).Count "$($app.id) output count"
        Assert-True ([string]$workflow.extra.linearData.outputs[0] -in $nodeIds) "$($app.id) output references a root node"
        Assert-True (@($workflow.nodes | Where-Object id -eq $workflow.extra.linearData.outputs[0]).type -in @('SaveImage','PreviewImage')) "$($app.id) exposes an image output"
    }
}

Test-Case 'studio app sync plan preserves catalog groups and app suffixes' {
    $plan = @(& $syncScript -PrintPlan)

    Assert-Equal 15 $plan.Count 'studio sync plan count'
    foreach ($id in $expectedIds) {
        Assert-True (@($plan | Where-Object { $_ -match "^$([regex]::Escape($id))\t.+\.app\.json$" }).Count -eq 1) "sync plan contains $id"
    }
}

Test-Case 'image-input apps ship with a ready local reference image' {
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    $imageInputApps = 0

    foreach ($app in $catalog.apps) {
        $workflow = Get-Content -LiteralPath (Join-Path $appsRoot $app.file) -Raw | ConvertFrom-Json
        $loadImages = @($workflow.nodes | Where-Object type -eq 'LoadImage')
        if ($loadImages.Count -eq 0) { continue }
        $imageInputApps++
        foreach ($node in $loadImages) {
            Assert-Equal 'studio-reference.webp' $node.widgets_values[0] "$($app.id) default input image"
        }
    }

    Assert-Equal 8 $imageInputApps 'apps with an image input'
    $reference = Join-Path $projectRoot 'data\input\studio-reference.webp'
    Assert-True ((Test-Path -LiteralPath $reference) -and (Get-Item -LiteralPath $reference).Length -gt 0) 'local reference image is installed'
}
