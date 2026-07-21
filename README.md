# ComfyUI local: six-model 8 GB setup

This is a pinned, tested ComfyUI installation for this PC's NVIDIA GeForce RTX 5060 Laptop GPU (8 GB). It includes six image models, four editable UI workflows, seven canvas presets, verified downloads, and a reproducible benchmark.

## Start

```powershell
cd C:\Users\Sushmit\Desktop\Code\comfyui-local
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

Open [http://127.0.0.1:8188](http://127.0.0.1:8188). The server is loopback-only; other devices cannot reach it.

In ComfyUI, load one of these files:

- `workflows\ui\realistic-sdxl.json` — RealVisXL by default; select Juggernaut in the checkpoint node for the second realistic style.
- `workflows\ui\anime-sdxl.json` — Animagine by default; select Illustrious in the checkpoint node for the second anime style.
- `workflows\ui\z-image-turbo.json` — fast photorealistic Z-Image.
- `workflows\ui\flux2-klein.json` — fastest four-step photorealistic model in this set.

Change width and height in the grouped node labelled **Canvas - edit width and height here**. The tested core orientations are square `1024 × 1024`, landscape `1216 × 832`, and portrait `832 × 1216`.

## Canvas presets

| Orientation | Label | Size | Ratio |
|---|---|---:|---:|
| Square | Square | 1024 × 1024 | 1:1 |
| Landscape | Standard | 1152 × 896 | 9:7 |
| Landscape | Photo | 1216 × 832 | 19:13 |
| Landscape | Wide | 1344 × 768 | 7:4 |
| Portrait | Standard | 896 × 1152 | 7:9 |
| Portrait | Photo | 832 × 1216 | 13:19 |
| Portrait | Tall | 768 × 1344 | 4:7 |

Use dimensions divisible by 16 for the modern workflows. The supplied presets are deliberately conservative for 8 GB VRAM.

## Useful commands

```powershell
# Quick runtime/config check; does not re-hash 44.5 GB
.\scripts\verify.ps1 -StaticOnly -SkipArtifactHashes

# Full independent model size and SHA-256 check
.\scripts\verify.ps1 -StaticOnly -RequireModels

# Recreate all 18 square/landscape/portrait proofs and metrics
.\scripts\benchmark.ps1

# Optional troubleshooting mode; the tested default is preferred
.\scripts\start.ps1 -LowVram
```

Press `Ctrl+C` in the launch terminal to stop ComfyUI. If the verified server is already running, `start.ps1` reports the existing URL instead of creating a duplicate.

## What is pinned

- ComfyUI commit `d0fec2ef7e7086533fde261de3fdb88289bdca9e`
- Python 3.13 isolated in `.venv`
- PyTorch `2.11.0+cu130`, torchvision `0.26.0+cu130`, torchaudio `2.11.0+cu130`
- Ten model artifacts with immutable revision URLs, exact byte counts, and SHA-256 digests
- Official workflow-template and front-end source commits

The choices follow ComfyUI's current [Python 3.13 and CUDA 13 guidance](https://docs.comfy.org/installation/system_requirements). ComfyUI's [dynamic VRAM system](https://github.com/Comfy-Org/ComfyUI/discussions/12699) is left at its tested default; do not add `--highvram` on this 8 GB GPU.

## Project map

- `model-manifest.json` — six models, prompts, settings, sources, licenses, artifact hashes
- `config\aspect-ratios.json` — the seven canvas presets
- `workflows\ui` — editable ComfyUI graphs
- `workflows\api` — minimal benchmark graphs
- `scripts\setup.ps1` — idempotent runtime provisioning
- `scripts\download-models.ps1` — resumable verified acquisition
- `scripts\sync-workflows.ps1` — deterministic official-workflow sync
- `scripts\benchmark.ps1` — generation, timing, GPU-memory sampling, proof copy
- `MODEL_COMPARISON.md` — model selection and measured statistics
- `results\proof` — the 18 generated proof PNGs (local, intentionally not committed)

The runtime checkout, environment, models, and generated images are ignored by Git because they are large or machine-specific. Reproducible configuration and evidence remain tracked.

## Rebuild from scratch

```powershell
.\scripts\setup.ps1
.\scripts\download-models.ps1
.\scripts\sync-workflows.ps1
.\scripts\verify.ps1 -StaticOnly -RequireModels
.\scripts\start.ps1
```

Model licenses differ. Review the linked model card before commercial deployment; the local comparison is technical guidance, not a grant of rights.
