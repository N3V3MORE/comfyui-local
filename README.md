# ComfyUI Local Studio: six models for 8 GB VRAM

This is a pinned ComfyUI installation for this PC's NVIDIA GeForce RTX 5060 Laptop GPU (8 GB). It provides six isolated image-generation apps, nine control/detail/upscale apps, seven aspect-ratio presets, verified model downloads, and reproducible local benchmarks.

## Start in Opera GX

```powershell
cd C:\Users\Sushmit\Desktop\Code\comfyui-local
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

Open [http://127.0.0.1:8188](http://127.0.0.1:8188), then:

1. Click **Workflows** in the left sidebar.
2. Expand **ComfyUI Local Studio**.
3. Open an app from **Create**, **Control**, **Detail**, **Reference**, or **Upscale**.
4. Change the controls in the right input panel and click **Run**.

The apps open in ComfyUI's simplified [App Mode](https://docs.comfy.org/interface/app-mode). Opera GX is supported because generation runs in the local ComfyUI server, not inside the browser. Generated files are saved under `results\images`.

For Control, Reference, and Upscale apps, select or upload an image in the right input panel before clicking Run. The bundled reference image keeps the underlying graph complete, but App Mode intentionally treats image inputs as a user choice.

## Six core generation apps

These are separate apps on purpose: each graph loads only the model, text encoder, and VAE belonging to its own architecture.

| App | Type | Best for | Steps | Measured average | Measured peak VRAM |
|---|---|---|---:|---:|---:|
| RealVisXL Natural Photo | Realistic | Natural people and everyday photography | 30 | 18.91 s | 7,726 MiB |
| Juggernaut Cinematic Photo | Realistic | Dramatic lighting and cinematic scenes | 35 | 21.71 s | 7,409 MiB |
| Animagine Anime | Anime | Rich modern anime character art | 28 | 18.18 s | 7,475 MiB |
| Illustrious Anime | Anime | Clean, detailed illustration | 30 | 19.64 s | 7,440 MiB |
| Z-Image Photoreal | Photorealistic | Faces, skin texture, and fast finished images | 8 | 9.27 s | 7,605 MiB |
| FLUX.2 Klein Photoreal | Photorealistic | Fast previews and strong prompt following | 4 | 5.23 s | 7,640 MiB |

Times are averages across square, landscape, and portrait runs on this PC. See [MODEL_COMPARISON.md](MODEL_COMPARISON.md) for payload, architecture, precision, per-orientation results, source cards, and license notes.

## Nine advanced apps

| Group | App | What it does | Required input |
|---|---|---|---|
| Control | SDXL Canny Control | Follows edges and composition | Image, prompt, aspect ratio |
| Control | SDXL Depth Control | Follows scene depth | Image, prompt, aspect ratio |
| Control | SDXL Pose Control | Follows a person's pose | Image, prompt, aspect ratio |
| Control | Z-Image Canny Control | Fast photorealistic edge control | Image and prompt |
| Reference | SDXL Reference Image | Guides style and composition with IPAdapter | Image and prompt |
| Detail | SDXL Face Detail | Generates and refines detected faces | Prompt and canvas size |
| Upscale | Photo Upscale 2x | Doubles photo dimensions | Image |
| Upscale | Photo Upscale 4x | Enlarges photos four times | Image |
| Upscale | Anime Upscale 4x | Enlarges anime line art four times | Image |

The advanced stack is pinned to five reviewed extensions and 11 support assets. Canny, depth, pose, Z-Image ControlNet, IPAdapter, FaceDetailer, and all three upscalers have completed real prompts through the live local server.

## Aspect ratios and orientations

| Orientation | App label | Size | Ratio |
|---|---|---:|---:|
| Square | Square 1:1 | 1024 × 1024 | 1:1 |
| Portrait | Portrait 4:5 | 896 × 1152 | 4:5 |
| Portrait | Photo Portrait 2:3 | 832 × 1216 | 2:3 |
| Portrait | Tall 9:16 | 768 × 1344 | 9:16 |
| Landscape | Landscape 5:4 | 1152 × 896 | 5:4 |
| Landscape | Photo Landscape 3:2 | 1216 × 832 | 3:2 |
| Landscape | Wide 16:9 | 1344 × 768 | 16:9 |

The four SDXL Create apps expose width and height directly. Control apps expose the named preset dropdown. Z-Image and FLUX.2 expose their model-safe width and height controls. The supplied sizes are divisible by 16 and conservative for 8 GB VRAM.

## Why the matrix-shape error happened

The earlier error was:

```text
RuntimeError: mat1 and mat2 shapes cannot be multiplied (512x2560 and 7680x3072)
```

This is a model-family mismatch, not an Opera GX problem. An SDXL, Z-Image, or FLUX.2 text encoder produced embeddings with a shape that a different model architecture could not accept. The Local Studio apps prevent this by isolating each family:

| Family | Loader shape |
|---|---|
| SDXL | One checkpoint supplies its matching model, CLIP encoders, and VAE |
| Z-Image | Z-Image diffusion model + matching Qwen encoder + Z-Image VAE |
| FLUX.2 | FLUX.2 Klein diffusion model + matching Qwen encoder + FLUX.2 VAE |

Do not swap loaders, text encoders, LoRAs, or conditioning links between these rows. Open another Local Studio app when changing families. The official Z-Image and [FLUX.2 Klein](https://docs.comfy.org/tutorials/flux/flux-2-klein) guides likewise define separate diffusion, text-encoder, and VAE files for their workflows.

## Verification and maintenance

```powershell
# Fast check: runtime, GPU, app JSON, and exact extension pins
.\scripts\verify.ps1 -StaticOnly -SkipArtifactHashes -RequireExtensions

# Full check: all core models, support assets, apps, nodes, and live HTTP server
.\scripts\verify.ps1 -RequireModels -RequireExtensions -RequireSupportAssets

# Recreate the 18 core model/orientation proofs and metrics
.\scripts\benchmark.ps1

# Fair shared prompts: one cold run, two warm runs, medians, and peak VRAM
.\scripts\benchmark.ps1 -Suite performance

# Optional quality stress suite plus a blind quality-ratings.csv sheet
.\scripts\benchmark.ps1 -Suite quality

# Optional troubleshooting mode; use only if the normal launch runs out of memory
.\scripts\start.ps1 -LowVram
```

Press `Ctrl+C` in the launch terminal to stop ComfyUI. If the verified server is already running, `start.ps1` reports the existing URL instead of creating a duplicate.

## What is pinned

- ComfyUI commit `d0fec2ef7e7086533fde261de3fdb88289bdca9e`
- Python 3.13 in `.venv`
- PyTorch `2.11.0+cu130`, torchvision `0.26.0+cu130`, torchaudio `2.11.0+cu130`
- Ten core model artifacts and 11 support assets with immutable URLs, byte counts, and SHA-256 digests
- Five exact extension commits plus the small tracked `comfyui_local_studio` node package
- Fifteen generated App Mode workflows installed by `scripts\setup.ps1`

ComfyUI's dynamic VRAM behaviour is left at its tested default. Do not add `--highvram` on this 8 GB GPU; close other GPU-heavy programs if a large canvas runs near the limit.

## Project map

- `config\models.json` — model families, components, precision, and sampling behaviour
- `config\artifacts.json` — all core and support downloads, roles, sizes, and SHA-256 hashes
- `config\workflow-specs.json` — the 15 apps, defaults, semantic inputs, and output paths
- `config\resolutions.json` — seven 8 GB-safe canvas presets
- `config\benchmark-scenarios.json` — orientation, performance, and optional quality scenarios
- `config\licenses.json` — model and support-asset licensing notes
- `extensions-manifest.json` — five extension repositories and exact commits
- `vendor\workflows` and `vendor\api` — pinned canonical templates with semantic node keys
- `src\comfy_local` — graph builder, validation, compiler, and benchmark prompt materializer
- `workflows\apps`, `workflows\ui`, and `workflows\api` — generated artifacts; do not edit by hand
- `scripts\setup.ps1` — idempotent runtime provisioning
- `scripts\download-models.ps1` — resumable, hash-verified downloads
- `scripts\compile.ps1` — deterministic workflow compiler entrypoint
- `scripts\install-workflows.ps1` — installs already-validated App Mode workflows
- `scripts\benchmark.ps1` — submission, timing, GPU-memory sampling, and proof collection

## Workflow compiler

Every editable template node used by automation has a stable `properties.studio_key`. The Python compiler selects these keys exactly once, applies the selected model profile, builds App Mode inputs, validates links and widgets, and only then serializes ComfyUI's numeric node and link IDs. This keeps family selection and graph mutation out of PowerShell.

After changing a model profile, workflow specification, template, or resolution, rebuild and test with:

```powershell
.\scripts\compile.ps1
.\tests\run-tests.ps1
```

Compilation produces 15 App Mode workflows, four editable UI workflows, and three API prompts. It writes files atomically and is deterministic: running it again without a configuration change produces the same content. To add an app, add one declarative entry to `config\workflow-specs.json`, reference an existing semantic template, and extend the compiler only when introducing genuinely new graph behaviour.

## Rebuild

```powershell
.\scripts\setup.ps1
.\scripts\download-models.ps1
.\scripts\compile.ps1
.\scripts\copy-bundled-inputs.ps1
.\scripts\install-workflows.ps1
.\scripts\verify.ps1 -StaticOnly -RequireModels -RequireExtensions -RequireSupportAssets
.\scripts\start.ps1
```

Model and extension licenses differ. Review each linked source card before redistribution, paid API use, or commercial deployment.
