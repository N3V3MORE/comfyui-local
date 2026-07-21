# ComfyUI Local Six-Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and prove a reproducible local ComfyUI installation with six curated image models and model-safe square, landscape, and portrait workflows on the RTX 5060 Laptop GPU.

**Architecture:** Keep a small tracked management repository around an ignored, pinned official ComfyUI checkout, ignored model payloads, and an isolated `uv` environment. Drive setup, downloads, workflows, validation, and benchmarking from tracked JSON contracts and focused PowerShell scripts; expose ComfyUI only on `127.0.0.1:8188`.

**Tech Stack:** Windows 11, PowerShell 7/5.1-compatible scripts, Git, `uv`, Python 3.13, PyTorch 2.11.0 CUDA 13.0, official ComfyUI core, JSON workflow files, `curl.exe`, and `nvidia-smi`.

## Global Constraints

- Project root is exactly `C:\Users\Sushmit\Desktop\Code\comfyui-local`.
- GPU target is exactly `NVIDIA GeForce RTX 5060 Laptop GPU` with 8,151 MiB VRAM.
- ComfyUI source is pinned to commit `d0fec2ef7e7086533fde261de3fdb88289bdca9e` from `https://github.com/Comfy-Org/ComfyUI.git`.
- Python is 3.13 in `.venv`; PyTorch packages are `torch==2.11.0+cu130`, `torchvision==0.26.0+cu130`, and `torchaudio==2.11.0+cu130`.
- ComfyUI listens only on `127.0.0.1:8188`.
- Models, `.venv`, the ComfyUI runtime checkout, raw logs, and generated images remain untracked.
- Model downloads require 70 GB free before starting, resume partial transfers, and pass exact SHA-256 verification before final placement.
- Batch size is one. Baseline generation uses 1024 x 1024; orientation proof adds 1216 x 832 and 832 x 1216.
- Do not install custom nodes or SageAttention before all core workflows have a recorded baseline.
- Any required `--lowvram` retry must be visible in benchmark results and documentation.

---

## File map

- `.gitignore`: excludes runtime state and generated artifacts only.
- `config/aspect-ratios.json`: single source of truth for seven canvas presets.
- `comfyui-version.json`: pinned upstream repository and commit.
- `model-manifest.json`: model metadata, artifact URLs, sizes, hashes, defaults, and benchmark profile.
- `requirements.in`: direct Python requirements and exact CUDA package pins.
- `requirements.lock.txt`: resolved environment lock generated with `uv pip compile`.
- `workflow-sources.json`: pinned official workflow-template sources.
- `scripts/lib/common.ps1`: path, JSON, command, hash, and assertion helpers.
- `scripts/setup.ps1`: runtime checkout, virtual environment, dependencies, and external model paths.
- `scripts/download-models.ps1`: resumable, verified model acquisition.
- `scripts/sync-workflows.ps1`: deterministic local workflow generation from pinned official sources.
- `scripts/start.ps1`: foreground loopback-only ComfyUI launch.
- `scripts/verify.ps1`: static environment, GPU, artifact, workflow, and HTTP checks.
- `scripts/benchmark.ps1`: queues fixed API workflows and captures duration and peak VRAM.
- `tests/run-tests.ps1`: dependency-free PowerShell test runner.
- `tests/config.tests.ps1`: validates configuration contracts.
- `tests/downloads.tests.ps1`: validates hashing and finalization using tiny fixtures.
- `tests/workflows.tests.ps1`: validates required workflow model names and canvas controls.
- `workflows/ui/*.json`: four browser workflows.
- `workflows/api/*.json`: three benchmark templates selected by profile.
- `README.md`: direct operating instructions.
- `MODEL_COMPARISON.md`: researched facts plus measured local results.

---

### Task 1: Configuration contracts and dependency-free tests

**Files:**
- Create: `.gitignore`
- Create: `config/aspect-ratios.json`
- Create: `comfyui-version.json`
- Create: `model-manifest.json`
- Create: `requirements.in`
- Create: `workflow-sources.json`
- Create: `scripts/lib/common.ps1`
- Create: `tests/run-tests.ps1`
- Create: `tests/config.tests.ps1`

**Interfaces:**
- Consumes: approved design specification.
- Produces: `Get-ProjectRoot`, `Read-Json`, `Assert-Condition`, `Get-FileSha256`, configuration schemas, and exact artifact records used by all later tasks.

- [ ] **Step 1: Create the failing configuration tests**

`tests/run-tests.ps1` must dot-source every `*.tests.ps1`, count failures, and exit non-zero. `tests/config.tests.ps1` must assert:

```powershell
$root = Split-Path -Parent $PSScriptRoot
$ratios = Get-Content "$root\config\aspect-ratios.json" -Raw | ConvertFrom-Json
$manifest = Get-Content "$root\model-manifest.json" -Raw | ConvertFrom-Json
$version = Get-Content "$root\comfyui-version.json" -Raw | ConvertFrom-Json

Assert-Equal 7 $ratios.presets.Count 'seven aspect-ratio presets'
Assert-Equal '1024x1024' $ratios.presets[0].id 'square is first'
Assert-Equal 6 $manifest.models.Count 'six model records'
Assert-Equal 10 $manifest.artifacts.Count 'ten downloadable artifacts'
Assert-Equal 44500000000 ($manifest.artifacts | Measure-Object bytes -Sum).Sum 1000000000 'payload is approximately 44.5 GB'
Assert-Equal 'd0fec2ef7e7086533fde261de3fdb88289bdca9e' $version.commit 'pinned ComfyUI commit'

foreach ($artifact in $manifest.artifacts) {
    Assert-True ($artifact.url -match '/resolve/[0-9a-f]{40}/') "$($artifact.id) URL is revision-pinned"
    Assert-True ($artifact.sha256 -match '^[0-9a-f]{64}$') "$($artifact.id) has SHA-256"
    Assert-True ($artifact.bytes -gt 0) "$($artifact.id) has a byte size"
}
```

- [ ] **Step 2: Run the tests and confirm they fail because contracts do not exist**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1`

Expected: non-zero exit with missing `config/aspect-ratios.json` or `model-manifest.json`.

- [ ] **Step 3: Implement the common helpers and configuration files**

`config/aspect-ratios.json` contains these exact presets:

```json
{
  "presets": [
    {"id":"1024x1024","label":"Square","width":1024,"height":1024,"ratio":"1:1","orientation":"square"},
    {"id":"1152x896","label":"Standard landscape","width":1152,"height":896,"ratio":"9:7","orientation":"landscape"},
    {"id":"1216x832","label":"Photo landscape","width":1216,"height":832,"ratio":"19:13","orientation":"landscape"},
    {"id":"1344x768","label":"Wide landscape","width":1344,"height":768,"ratio":"7:4","orientation":"landscape"},
    {"id":"896x1152","label":"Standard portrait","width":896,"height":1152,"ratio":"7:9","orientation":"portrait"},
    {"id":"832x1216","label":"Photo portrait","width":832,"height":1216,"ratio":"13:19","orientation":"portrait"},
    {"id":"768x1344","label":"Tall portrait","width":768,"height":1344,"ratio":"4:7","orientation":"portrait"}
  ]
}
```

`comfyui-version.json` contains:

```json
{
  "repository": "https://github.com/Comfy-Org/ComfyUI.git",
  "commit": "d0fec2ef7e7086533fde261de3fdb88289bdca9e",
  "python": "3.13",
  "torchIndex": "https://download.pytorch.org/whl/cu130",
  "torch": "2.11.0+cu130",
  "torchvision": "0.26.0+cu130",
  "torchaudio": "2.11.0+cu130"
}
```

`workflow-sources.json` pins:

```json
{
  "sdxl": "https://raw.githubusercontent.com/Comfy-Org/ComfyUI_frontend/24d928409605c3a01c0fb9857d024c7bb1572597/browser_tests/assets/default.json",
  "zImage": "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/93f3058d5ad87d83c5eab7c0eabd734738376816/templates/image_z_image_turbo.json",
  "flux2": "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/93f3058d5ad87d83c5eab7c0eabd734738376816/templates/image_flux2_klein_text_to_image.json"
}
```

`model-manifest.json` defines six `models` and these ten exact artifact contracts:

| id | target | bytes | sha256 |
|---|---|---:|---|
| realvis-xl-v5 | `checkpoints/realistic/RealVisXL_V5.0_fp16.safetensors` | 6938065488 | `6a35a7855770ae9820a3c931d4964c3817b6d9e3c6f9c4dabb5b3a94e5643b80` |
| juggernaut-xl-v9 | `checkpoints/realistic/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors` | 7105348188 | `c9e3e68f89b8e38689e1097d4be4573cf308de4e3fd044c64ca697bdb4aa8bca` |
| animagine-xl-4-opt | `checkpoints/anime/animagine-xl-4.0-opt.safetensors` | 6938350040 | `6327eca98bfb6538dd7a4edce22484a1bbc57a8cff6b11d075d40da1afb847ac` |
| illustrious-xl-v2 | `checkpoints/anime/Illustrious-XL-v2.0.safetensors` | 6938040674 | `c2a1a3eaa13d4c107dc7e00c3fe830cab427aa026362740ea094745b3422a331` |
| z-image-nvfp4 | `diffusion_models/z_image_turbo_nvfp4.safetensors` | 4509509600 | `a553c889dbcb910de4c98293237573219a37007c1074a3f04576646a088bd5c8` |
| z-image-qwen-fp4 | `text_encoders/qwen_3_4b_fp4_mixed.safetensors` | 3479416193 | `7ca32dcf07dfe7692945d80fff86e3a74cb83c6206b9b223ac6836b939bb85d6` |
| z-image-vae | `vae/ae.safetensors` | 335304388 | `afc8e28272cd15db3919bacdb6918ce9c1ed22e96cb12c4d5ed0fba823529e38` |
| flux2-klein-fp8 | `diffusion_models/flux-2-klein-4b-fp8.safetensors` | 4070624520 | `97ed34fe0567e436200f2faee3939b88f2b5d99f8af2a4dc16532c4245c0ccb6` |
| flux2-qwen-fp4 | `text_encoders/qwen_3_4b_fp4_flux2.safetensors` | 3848213998 | `3eab03a77adb0ee5304a4e677d5c10ac22f9049c1d7c894adca4f8bb39206ca8` |
| flux2-vae | `vae/flux2-vae.safetensors` | 336211292 | `868fe7b343cc8f3a19dbcfcafbc3d5f888802be3f89bd81b65b3621a066ce8f3` |

Each artifact URL is `https://huggingface.co/<repo>/resolve/<recorded-revision>/<source-path>?download=true` using the exact revisions captured in the design research. Each model record contains `id`, `name`, `category`, `family`, `parameters`, `precision`, `license`, `artifacts`, `workflowProfile`, `steps`, `cfg`, `sampler`, `scheduler`, positive prompt, and negative prompt.

`requirements.in` contains the exact CUDA pins followed by the dependencies from the pinned ComfyUI `requirements.txt`; do not leave unbounded `torch`, `torchvision`, or `torchaudio` entries.

- [ ] **Step 4: Run configuration tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1`

Expected: all configuration tests pass and print a final `PASS` count with zero failures.

- [ ] **Step 5: Commit**

```powershell
git add .gitignore config comfyui-version.json model-manifest.json requirements.in workflow-sources.json scripts/lib tests
git commit -m "build: define ComfyUI installation contracts"
```

---

### Task 2: Reproducible ComfyUI runtime setup

**Files:**
- Create: `scripts/setup.ps1`
- Create: `tests/setup.tests.ps1`
- Create: `requirements.lock.txt` by running the pinned resolver command.

**Interfaces:**
- Consumes: `comfyui-version.json`, `requirements.in`, `Get-ProjectRoot`, `Read-Json`, and `Assert-Condition`.
- Produces: ignored `ComfyUI/`, ignored `.venv/`, `ComfyUI/extra_model_paths.yaml`, and a repeatable setup command.

- [ ] **Step 1: Add failing setup contract tests**

The tests invoke `setup.ps1 -ValidateOnly` and assert that output names Git, `uv`, `nvidia-smi`, Python 3.13, the expected GPU, and the required 70 GB disk threshold. A second test imports the script's YAML builder and compares the exact output:

```yaml
comfyui_local:
  base_path: C:/Users/Sushmit/Desktop/Code/comfyui-local/models
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  text_encoders: text_encoders
  vae: vae
```

- [ ] **Step 2: Run the setup tests and confirm failure**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1`

Expected: failure because `scripts/setup.ps1` does not exist.

- [ ] **Step 3: Implement `setup.ps1`**

Required control flow:

```powershell
[CmdletBinding(SupportsShouldProcess)]
param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = Get-Content "$root\comfyui-version.json" -Raw | ConvertFrom-Json

# Validate exact commands, GPU name, driver visibility, and free bytes.
# Exit here when -ValidateOnly is present.
# Clone only when ComfyUI/.git is absent.
git -C $root clone --filter=blob:none $version.repository ComfyUI
git -C "$root\ComfyUI" fetch origin $version.commit --depth 1
git -C "$root\ComfyUI" checkout --detach $version.commit
uv venv --python $version.python "$root\.venv"
uv pip sync --python "$root\.venv\Scripts\python.exe" "$root\requirements.lock.txt"
# Write extra_model_paths.yaml using forward slashes and create model folders.
```

If `ComfyUI/` already exists, verify it is the expected repository and checkout the pinned commit without deleting user data. If `.venv` exists, synchronize it. Do not use `--listen 0.0.0.0`, administrator privileges, or global `pip`.

- [ ] **Step 4: Generate the lock file**

Run:

```powershell
uv pip compile --python-version 3.13 --python-platform windows `
  --index-url https://pypi.org/simple `
  --extra-index-url https://download.pytorch.org/whl/cu130 `
  --index-strategy unsafe-best-match `
  --output-file requirements.lock.txt requirements.in
```

Expected: a lock containing the three exact CUDA packages and ComfyUI frontend package `1.45.21`, workflow templates `0.11.12`, embedded docs `0.5.8`, and `comfy-kitchen==0.2.22`.

- [ ] **Step 5: Run tests, then provision the runtime**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup.ps1
.\.venv\Scripts\python.exe -c "import torch; print(torch.__version__); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"
```

Expected: tests pass; Python reports `2.11.0+cu130`, `True`, and `NVIDIA GeForce RTX 5060 Laptop GPU`.

- [ ] **Step 6: Commit**

```powershell
git add scripts/setup.ps1 tests/setup.tests.ps1 requirements.lock.txt
git commit -m "build: provision pinned ComfyUI runtime"
```

---

### Task 3: Resumable verified model downloader

**Files:**
- Create: `scripts/download-models.ps1`
- Create: `tests/downloads.tests.ps1`
- Modify: `scripts/lib/common.ps1`

**Interfaces:**
- Consumes: artifact records `{id,url,target,bytes,sha256}` and the project `models/` directory.
- Produces: `Get-FileSha256`, `Test-Artifact`, and `Install-Artifact`; only verified final model paths are visible to ComfyUI.

- [ ] **Step 1: Write failing fixture tests**

Tests create a small file under `$TestDrive` or a uniquely named directory under `work/test-downloads`, assert its SHA-256, assert a wrong digest fails, and assert an already-valid destination is skipped. The test cleans only its exact resolved directory.

- [ ] **Step 2: Run tests and confirm failure**

Expected: failure because `Install-Artifact` is not defined.

- [ ] **Step 3: Implement the downloader**

The finalization contract is:

```powershell
function Install-Artifact {
    param($Artifact, [string]$ModelsRoot)
    $destination = Join-Path $ModelsRoot $Artifact.target
    $partial = "$destination.partial"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null

    if (Test-Artifact $destination $Artifact.bytes $Artifact.sha256) { return 'skipped' }
    & curl.exe --location --fail --retry 5 --retry-delay 5 --continue-at - `
        --output $partial $Artifact.url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $($Artifact.id)" }
    if (-not (Test-Artifact $partial $Artifact.bytes $Artifact.sha256)) {
        throw "Integrity check failed: $($Artifact.id)"
    }
    Move-Item -LiteralPath $partial -Destination $destination -Force
    return 'installed'
}
```

The script validates 70 GB free before the first missing artifact, supports `-Id <artifact-id>` and `-VerifyOnly`, prints progress one artifact at a time, and never deletes a valid destination.

- [ ] **Step 4: Run tests**

Expected: valid fixture installs, invalid hash fails, valid existing file skips, and no file outside the test directory changes.

- [ ] **Step 5: Commit**

```powershell
git add scripts/lib/common.ps1 scripts/download-models.ps1 tests/downloads.tests.ps1
git commit -m "feat: add verified resumable model downloads"
```

---

### Task 4: Browser workflows and orientation controls

**Files:**
- Create: `scripts/sync-workflows.ps1`
- Create: `tests/workflows.tests.ps1`
- Create: `workflows/ui/realistic-sdxl.json`
- Create: `workflows/ui/anime-sdxl.json`
- Create: `workflows/ui/z-image-turbo.json`
- Create: `workflows/ui/flux2-klein.json`

**Interfaces:**
- Consumes: `workflow-sources.json`, exact model filenames, and canvas presets.
- Produces: four loadable core-node workflows with visible 1024 x 1024 canvas defaults and model-specific defaults.

- [ ] **Step 1: Add failing workflow tests**

The tests assert all four files parse as JSON, contain no `http://`, contain no `resolve/main`, use version `0.4`, and contain these exact strings:

```text
realistic-sdxl.json: RealVisXL_V5.0_fp16.safetensors, 1024, 30
anime-sdxl.json: animagine-xl-4.0-opt.safetensors, 1024, 28
z-image-turbo.json: z_image_turbo_nvfp4.safetensors, qwen_3_4b_fp4_mixed.safetensors, ae.safetensors, 1024, 8
flux2-klein.json: flux-2-klein-4b-fp8.safetensors, qwen_3_4b_fp4_flux2.safetensors, flux2-vae.safetensors, 1024, 4
```

- [ ] **Step 2: Run tests and confirm failure**

Expected: missing workflow files.

- [ ] **Step 3: Implement deterministic workflow synchronization**

`sync-workflows.ps1` downloads the three pinned sources. For the two SDXL copies, find nodes by `type`, then set:

```powershell
($real.nodes | Where-Object type -eq 'CheckpointLoaderSimple').widgets_values[0] = 'realistic\RealVisXL_V5.0_fp16.safetensors'
($real.nodes | Where-Object type -eq 'EmptyLatentImage').widgets_values = @(1024, 1024, 1)
($real.nodes | Where-Object type -eq 'KSampler').widgets_values = @(246813579, 'fixed', 30, 5.0, 'dpmpp_2m', 'karras', 1.0)

($anime.nodes | Where-Object type -eq 'CheckpointLoaderSimple').widgets_values[0] = 'anime\animagine-xl-4.0-opt.safetensors'
($anime.nodes | Where-Object type -eq 'EmptyLatentImage').widgets_values = @(1024, 1024, 1)
($anime.nodes | Where-Object type -eq 'KSampler').widgets_values = @(246813579, 'fixed', 28, 5.0, 'euler_ancestral', 'normal', 1.0)
```

Set positive and negative prompts from the manifest. For modern templates, replace only exact model filenames throughout the parsed object before writing:

```text
qwen_3_4b.safetensors -> qwen_3_4b_fp4_mixed.safetensors (Z-Image)
z_image_turbo_bf16.safetensors -> z_image_turbo_nvfp4.safetensors
qwen_3_4b.safetensors -> qwen_3_4b_fp4_flux2.safetensors (FLUX.2)
```

The selected subgraphs already expose width and height primitives. Preserve official node definitions and set both to 1024. Write UTF-8 without BOM and stable JSON depth 100.

- [ ] **Step 4: Generate workflows and run tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-workflows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Expected: four valid workflows and all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add scripts/sync-workflows.ps1 tests/workflows.tests.ps1 workflows/ui
git commit -m "feat: add model and orientation workflows"
```

---

### Task 5: Start and static verification commands

**Files:**
- Create: `scripts/start.ps1`
- Create: `scripts/verify.ps1`
- Create: `tests/runtime.tests.ps1`

**Interfaces:**
- Consumes: pinned runtime, manifest, workflows, and `-LowVram` launch choice.
- Produces: foreground ComfyUI process and a machine-readable verification summary.

- [ ] **Step 1: Add failing runtime tests**

Tests assert `start.ps1 -PrintCommand` includes `.venv\Scripts\python.exe`, `ComfyUI\main.py`, `--listen 127.0.0.1`, and `--port 8188`; `-LowVram` adds exactly `--lowvram`. Tests assert `verify.ps1 -StaticOnly` rejects missing runtime paths and reports artifact counts without starting ComfyUI.

- [ ] **Step 2: Run tests and confirm failure**

Expected: missing start and verify scripts.

- [ ] **Step 3: Implement foreground launch**

```powershell
[CmdletBinding()]
param([switch]$LowVram, [switch]$PrintCommand)
$args = @("$root\ComfyUI\main.py", '--listen', '127.0.0.1', '--port', '8188', '--preview-method', 'auto')
if ($LowVram) { $args += '--lowvram' }
if ($PrintCommand) { Write-Output ((@($python) + $args) -join ' '); exit 0 }
& $python @args
exit $LASTEXITCODE
```

Before launch, probe `http://127.0.0.1:8188/system_stats`. If healthy, return the existing instance instead of creating a second server. If the port is occupied by another process, report the PID and fail.

- [ ] **Step 4: Implement verification**

`verify.ps1` checks Git commit, Python 3.13, exact CUDA package versions, `torch.cuda.is_available()`, GPU name, VRAM greater than 7.5 GiB, model file count and hashes, workflow files, and—unless `-StaticOnly`—HTTP 200 plus `/system_stats` device data. Output both readable lines and `results/verification.json`.

- [ ] **Step 5: Run tests and static verification**

Expected: tests pass. Static verification may report models as not yet downloaded but must distinguish `missing` from `invalid`.

- [ ] **Step 6: Commit**

```powershell
git add scripts/start.ps1 scripts/verify.ps1 tests/runtime.tests.ps1
git commit -m "feat: add local launch and verification"
```

---

### Task 6: API fixtures and benchmark runner

**Files:**
- Create: `workflows/api/sdxl.json`
- Create: `workflows/api/z-image-turbo.json`
- Create: `workflows/api/flux2-klein.json`
- Create: `scripts/benchmark.ps1`
- Create: `tests/benchmark.tests.ps1`

**Interfaces:**
- Consumes: model benchmark profiles, three API templates, canvas presets, running ComfyUI `/prompt`, `/history/<id>`, and `nvidia-smi`.
- Produces: `results/bench/<timestamp>/summary.json`, `summary.csv`, per-run logs, images created by ComfyUI, and explicit normal/low-VRAM status.

- [ ] **Step 1: Add failing API workflow and mutation tests**

Assert each API fixture is an object keyed by numeric node IDs, every node has `class_type` and `inputs`, and each profile mutation produces the correct model, steps, prompt, seed, width, height, and filename prefix for square, photo landscape, and photo portrait.

- [ ] **Step 2: Run tests and confirm failure**

Expected: API fixtures and benchmark script are missing.

- [ ] **Step 3: Create the three minimal API fixtures**

The SDXL graph contains `CheckpointLoaderSimple -> CLIPTextEncode positive/negative -> KSampler <- EmptyLatentImage -> VAEDecode -> SaveImage`.

The Z-Image graph contains:

```text
UNETLoader(z_image_turbo_nvfp4) -> ModelSamplingAuraFlow(shift=3) -> KSampler
CLIPLoader(qwen_3_4b_fp4_mixed, type=lumina2) -> positive -> ConditioningZeroOut -> KSampler
EmptySD3LatentImage -> KSampler(8 steps, cfg=1, res_multistep, simple)
VAELoader(ae) + KSampler -> VAEDecode -> SaveImage
```

The FLUX.2 graph contains:

```text
UNETLoader(flux-2-klein-4b-fp8) + CLIPLoader(qwen_3_4b_fp4_flux2, type=flux2)
CLIPTextEncode -> ConditioningZeroOut -> CFGGuider(cfg=1)
RandomNoise + KSamplerSelect(euler) + Flux2Scheduler(4 steps, width, height)
EmptyFlux2LatentImage -> SamplerCustomAdvanced -> VAEDecode(flux2-vae) -> SaveImage
```

Use the exact core input names returned by the pinned runtime's `/object_info` endpoint and validate every fixture through `/prompt` before considering the task complete.

- [ ] **Step 4: Implement benchmark orchestration**

`benchmark.ps1` accepts `-ModelId`, `-Orientation square|landscape|portrait`, and `-LowVramRecorded`. With no filters it runs all six models across `1024x1024`, `1216x832`, and `832x1216`. For each job it:

1. clones the profile's JSON object in memory;
2. sets model filenames, prompts, seed `246813579`, dimensions, steps, CFG, and prefix;
3. samples `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits` every 500 ms in a background job;
4. POSTs `{prompt:<workflow>,client_id:<guid>}` to `/prompt`;
5. polls `/history/<prompt_id>` every second with a 20-minute timeout;
6. records success, Comfy error text, elapsed seconds, peak observed MiB, output filename, and low-VRAM mode;
7. stops and removes its sampler job in `finally`.

- [ ] **Step 5: Run tests and a no-model contract check**

Expected: all offline mutation tests pass; the live benchmark refuses cleanly if ComfyUI is unavailable or required weights are missing.

- [ ] **Step 6: Commit**

```powershell
git add workflows/api scripts/benchmark.ps1 tests/benchmark.tests.ps1
git commit -m "feat: add reproducible ComfyUI benchmarks"
```

---

### Task 7: Acquire models and prove all six profiles

**Files:**
- Generate (ignored): `models/**`
- Generate (ignored): `results/verification.json`
- Generate (ignored): `results/bench/<timestamp>/**`

**Interfaces:**
- Consumes: completed setup, downloader, launch, verification, and benchmark commands.
- Produces: verified model files and current-machine evidence for every model and orientation.

- [ ] **Step 1: Download and verify all artifacts**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\download-models.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\download-models.ps1 -VerifyOnly
```

Expected: ten valid artifacts, approximately 44.5 GB total, zero hash failures.

- [ ] **Step 2: Start ComfyUI and verify health**

Start `scripts/start.ps1` in a hidden background process with logs under `results/runtime`, then run `scripts/verify.ps1`.

Expected: HTTP 200, the pinned GPU in `/system_stats`, and six model profiles ready.

- [ ] **Step 3: Run square smoke benchmarks first**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1 -Orientation square
```

Expected: six successful 1024 x 1024 images. If one model OOMs, restart with `start.ps1 -LowVram`, rerun only that model, and record the retry.

- [ ] **Step 4: Run landscape and portrait proof**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1 -Orientation landscape
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1 -Orientation portrait
```

Expected: one 1216 x 832 and one 832 x 1216 image from each model.

- [ ] **Step 5: Inspect the 18 output images**

Open contact sheets or representative outputs and reject blank, corrupt, all-noise, or obviously failed generations even if the API reports success. Record any model-specific caveat.

---

### Task 8: User documentation, measured comparison, and final gate

**Files:**
- Create: `README.md`
- Create: `MODEL_COMPARISON.md`
- Modify: `model-manifest.json` only if verified launch flags differ from expected defaults.

**Interfaces:**
- Consumes: official-source research and current `summary.csv`/`summary.json` evidence.
- Produces: direct operating instructions and the requested per-model comparison table with sourced facts separated from local measurements.

- [ ] **Step 1: Write documentation validation tests**

Add assertions that README contains exact commands for setup, download, start, stop with Ctrl+C, verify, benchmark, changing width/height, all seven aspect ratios, output locations, updating the pinned revision, and troubleshooting OOM. Assert the comparison contains all six model names and columns for category, family, parameters, precision, payload, resolution, steps, license, strengths, limitations, measured seconds, peak MiB, and launch mode.

- [ ] **Step 2: Run tests and confirm documentation checks fail**

Expected: missing README and comparison sections.

- [ ] **Step 3: Write `README.md`**

Lead with:

```powershell
cd C:\Users\Sushmit\Desktop\Code\comfyui-local
.\scripts\start.ps1
```

Then give the URL `http://127.0.0.1:8188`, the four workflow paths, canvas table, and concise recovery commands. State that first model load is slower and only one model should be queued at a time on 8 GB VRAM.

- [ ] **Step 4: Write `MODEL_COMPARISON.md` from evidence**

Keep two explicit sections:

1. `Source facts`: model family, parameter count, local precision, payload, recommended resolution/steps, license, strengths, and known limitations with direct official links.
2. `Measured on this laptop`: GPU, driver, Comfy commit, Torch version, orientation, elapsed seconds, peak observed MiB, launch mode, and result.

Do not label observed `nvidia-smi` sampling as exact allocation; call it peak observed GPU memory.

- [ ] **Step 5: Run full verification**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify.ps1
git diff --check
git status --short
```

Expected: all tests and verification pass; only intentional tracked documentation changes remain.

- [ ] **Step 6: Commit**

```powershell
git add README.md MODEL_COMPARISON.md model-manifest.json tests
git commit -m "docs: document verified local image generation"
```

- [ ] **Step 7: Final live smoke check**

Restart with the documented default command, probe `http://127.0.0.1:8188`, open the UI, load each of the four UI workflows, and confirm no required node is missing. Leave the healthy local instance running unless the user asks to stop it.
