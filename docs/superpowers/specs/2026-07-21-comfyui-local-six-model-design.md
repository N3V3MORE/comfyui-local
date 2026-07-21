# ComfyUI Local Six-Model Design

Date: 2026-07-21  
Status: Approved for implementation planning

## Purpose

Build a clear, reproducible ComfyUI installation at
`C:\Users\Sushmit\Desktop\Code\comfyui-local` for the laptop's NVIDIA GeForce
RTX 5060 Laptop GPU. The installation will provide six complementary local
image-generation models, model-safe landscape and portrait presets, starter
workflows, verified downloads, and measured results from the actual machine.

The machine observed during discovery has:

- NVIDIA GeForce RTX 5060 Laptop GPU with 8,151 MiB VRAM
- AMD Ryzen AI 7 350 with 8 cores and 16 logical processors
- 31.3 GB system RAM
- approximately 536 GB free on `C:`
- Windows 11 Pro
- Git, Python 3.13, `uv`, Node.js, and current NVIDIA drivers available

The main design constraint is 8 GB of VRAM. Disk space and system RAM are
adequate for a curated model library and ComfyUI's model offloading.

## Goals

- Keep the setup understandable to someone opening the folder for the first
  time.
- Keep upstream ComfyUI source separate from local scripts, models, workflows,
  and documentation.
- Use an isolated Python 3.13 environment and a CUDA 13 PyTorch build suitable
  for the RTX 50-series GPU.
- Provide two realistic, two anime, and two modern photorealistic models.
- Provide square, landscape, wide-landscape, portrait, and tall-portrait canvas
  presets without adding a custom aspect-ratio node.
- Use resumable downloads and verify every downloaded model against its known
  SHA-256 digest.
- Start ComfyUI on loopback only and return a working local URL.
- Generate one fixed-seed smoke image with every model and record elapsed time,
  peak VRAM, output resolution, and success or failure.
- Leave the repository carrying the operational truth through scripts,
  manifests, workflows, documentation, and benchmark artifacts.

## Non-goals

- Video generation, training, LoRA training, ControlNet packs, or large
  upscaler collections in the initial installation.
- Exposing ComfyUI to the LAN or internet.
- Installing a broad custom-node collection before the core workflows work.
- Automatically changing the Windows page file, NVIDIA driver, or power plan.
- Claiming a model fits 8 GB until it has completed a local generation.

## Chosen approach

Use a small management repository with an ignored runtime checkout of official
ComfyUI. A setup script will clone a recorded ComfyUI revision and create an
isolated `uv` environment. Local models will live outside that checkout and be
connected using ComfyUI's `extra_model_paths.yaml` mechanism.

This was selected over:

1. **Windows portable:** quick to extract, but Python and package state are less
   transparent and local additions tend to become mixed into the distribution.
2. **ComfyUI Desktop:** convenient, but parts of the installation live outside
   the requested Code folder, and its stable release can lag model support found
   in current ComfyUI core.

The manual layout makes updates explicit, keeps model files reusable, and lets
the scripts verify exactly what is installed.

## Repository layout

```text
comfyui-local/
|-- ComfyUI/                       # ignored official runtime checkout
|-- .venv/                         # ignored isolated Python environment
|-- models/                        # ignored downloaded model payloads
|   |-- checkpoints/
|   |   |-- realistic/
|   |   `-- anime/
|   |-- diffusion_models/
|   |-- text_encoders/
|   `-- vae/
|-- workflows/
|   |-- ui/                        # workflows opened in the browser UI
|   `-- api/                       # fixed benchmark workflow payloads
|-- scripts/
|   |-- setup.ps1
|   |-- download-models.ps1
|   |-- start.ps1
|   |-- verify.ps1
|   `-- benchmark.ps1
|-- docs/
|   `-- superpowers/specs/
|-- results/                       # ignored generated images and raw logs
|-- model-manifest.json
|-- comfyui-version.json
|-- requirements.lock.txt
|-- MODEL_COMPARISON.md
|-- README.md
`-- .gitignore
```

Tracked files will describe and reproduce the installation. Large downloaded
weights, the runtime checkout, virtual environment, logs, and generated images
will not be committed.

## Model selection

Download sizes are approximate decimal sizes. The exact source revision, target
path, file size, SHA-256, license, and default settings will live in
`model-manifest.json`.

| Category | Model | Architecture and local precision | Approx. payload | Default canvas | Steps | License and role |
|---|---|---|---:|---|---:|---|
| Realistic | RealVisXL V5.0 | SDXL, about 3B parameters, FP16 | 6.94 GB | 1024 x 1024 | 30 | OpenRAIL++; general people, scenes, and photographic realism |
| Realistic | Juggernaut XL v9 | SDXL, about 3B parameters, FP16 | 7.11 GB | 1024 x 1024 | 35 | CreativeML Open RAIL-M; cinematic realism, natural texture, and mature SDXL tooling; paid API deployment needs separate permission |
| Anime | Animagine XL 4.0 Opt | SDXL, about 3B parameters, FP16 | 6.94 GB | 1024 x 1024 | 28 | OpenRAIL++; clean modern anime using tag-oriented prompts |
| Anime | Illustrious XL v2.0 | SDXL, about 3B parameters, FP16 | 6.94 GB | 1024 x 1024 | 30 | CreativeML Open RAIL-M; broader character and style knowledge with a mature LoRA ecosystem |
| Photorealistic | Z-Image Turbo | 6B DiT, NVFP4 diffusion model plus FP4-mixed Qwen3 text encoder | 8.32 GB combined | 1024 x 1024 | 8 | Apache 2.0; modern photorealism, bilingual text rendering, and strong instruction following |
| Photorealistic | FLUX.2 Klein 4B distilled | 4B rectified-flow model in FP8 plus FP4 Qwen3 text encoder | 8.25 GB combined | 1024 x 1024 | 4 | Apache 2.0; concise prompt following plus text-to-image and reference-image editing |

The estimated model payload is about 44.5 GB. The complete environment should
remain below approximately 55 GB before generated outputs. The download script
will require at least 70 GB free before starting so partial files and package
installation have safe headroom.

The two modern models use reduced precision deliberately. Z-Image's NVFP4 file
targets the laptop's Blackwell-generation GPU. FLUX.2 Klein uses an FP8 diffusion
model and a smaller text encoder to make dynamic offloading practical. These are
expected fits, not acceptance evidence; both must complete the benchmark.

## Canvas and orientation presets

Every UI workflow will contain a clearly labelled `Canvas` group. Width and
height remain ordinary core-node values, so users can see and change them
without learning a custom node. Presets remain close to one megapixel and use
dimensions divisible by 64, which avoids needless VRAM spikes and suits the
SDXL models.

| Preset | Width | Height | Actual ratio | Orientation | Intended use |
|---|---:|---:|---:|---|---|
| Square | 1024 | 1024 | 1:1 | Square | avatars, products, balanced scenes |
| Standard landscape | 1152 | 896 | 9:7 | Landscape | people in environments, general photography |
| Photo landscape | 1216 | 832 | 19:13 | Landscape | wider camera-like composition |
| Wide landscape | 1344 | 768 | 7:4 | Wide landscape | banners, cinematic scenes, establishing shots |
| Standard portrait | 896 | 1152 | 7:9 | Portrait | portraits and fashion |
| Photo portrait | 832 | 1216 | 13:19 | Portrait | full-body and poster composition |
| Tall portrait | 768 | 1344 | 4:7 | Tall portrait | phone wallpaper and character art |

The README and workflow notes will call the 19:13 and 13:19 presets
"3:2-style" because the dimensions are model-friendly approximations rather
than exact photographic 3:2. Likewise, 7:4 is a model-friendly wide format,
not exact 16:9.

Initial verification uses the square preset for fair timing. After all six
models pass, the benchmark will also generate one landscape and one portrait
sample per model to prove orientation changes work. Batch size remains one.

## Workflows

Four short browser workflows will be tracked:

1. `realistic-sdxl.json` switches between RealVisXL and Juggernaut using the
   standard checkpoint loader.
2. `anime-sdxl.json` switches between Animagine and Illustrious and includes
   visible examples of tag prompting and a restrained negative prompt.
3. `z-image-turbo.json` uses the current ComfyUI core Z-Image nodes and the
   Blackwell-oriented model files.
4. `flux2-klein.json` uses the current ComfyUI core FLUX.2 Klein workflow and
   exposes the reference-image input without requiring it for text-to-image.

Each workflow will group nodes by `Model`, `Prompt`, `Canvas`, `Sampling`, and
`Output`. Model-specific defaults will be visible in notes. There will be no
hidden wildcard system, external prompt plugin, or unnecessary post-processing
chain.

Matching API payloads will use fixed prompts and seeds for repeatable smoke tests.
They are benchmark fixtures, not a second workflow implementation.

## Scripts and responsibilities

- `setup.ps1` validates prerequisites, clones the recorded ComfyUI revision,
  creates `.venv`, installs the locked CUDA environment, and writes
  `extra_model_paths.yaml`.
- `download-models.ps1` reads `model-manifest.json`, creates target folders,
  resumes partial downloads, checks expected size, verifies SHA-256, and leaves
  existing valid files untouched.
- `start.ps1` runs the recorded environment on `127.0.0.1:8188`. It starts with
  ComfyUI's default dynamic memory behavior and does not expose the service to
  the network.
- `verify.ps1` checks the repository revision, Python and package state, CUDA
  availability, GPU name and VRAM, model hashes, expected workflow files, and an
  HTTP health probe.
- `benchmark.ps1` queues the fixed API workflows, samples `nvidia-smi`, records
  wall-clock time and peak observed VRAM, and writes raw logs plus a concise
  summary used by `MODEL_COMPARISON.md`.

All scripts will use strict error handling, resolve paths from their own
location, avoid administrator privileges, and return a non-zero exit code on a
failed required check. Repeated logic will be kept in small functions with
descriptive names rather than compressed one-liners.

## Data flow

1. `model-manifest.json` defines every downloadable file and its destination.
2. The download script writes verified files under the external `models/`
   tree.
3. `extra_model_paths.yaml` makes those folders visible to the ignored ComfyUI
   checkout.
4. A UI or API workflow selects a model and canvas dimensions, then queues a
   generation through local ComfyUI.
5. ComfyUI loads and offloads components between VRAM and system RAM as needed.
6. Generated images and logs go to ignored `results/` folders.
7. The benchmark summary updates the human-readable comparison with measured
   machine-specific evidence.

## Failure handling

- A download uses a partial file and resumes when possible. A hash mismatch
  keeps the invalid file out of the final model path and reports the expected
  and actual digest.
- Setup stops before package installation if the NVIDIA GPU, driver, Python, Git,
  `uv`, free space, or network prerequisites are unsuitable.
- If a model runs out of VRAM at the one-megapixel preset, record the failure,
  retry once with ComfyUI's `--lowvram` mode, and record that mode explicitly.
- If the low-VRAM retry fails, reduce to a documented 768-pixel test only for
  diagnosis. A reduced-resolution pass does not satisfy the 1024-class
  acceptance criterion.
- SageAttention or third-party performance nodes may be evaluated only after a
  clean core baseline. They will not be silently added to make a failing model
  appear supported.
- The start script detects an occupied port and reports the owning process or
  returns the already-running ComfyUI health result instead of starting a second
  instance.

## Updates and reproducibility

`comfyui-version.json` records the upstream repository URL and exact tested
commit. `requirements.lock.txt` records the tested Python dependency set,
including exact PyTorch packages. Setup uses those records and never tracks an
unreviewed moving branch.

Updating ComfyUI will be a deliberate operation: fetch a selected upstream
revision, rebuild or synchronize the environment, run verification, and rerun
the six-model benchmark. The recorded revision changes only after all required
checks pass.

## Security and licensing

- ComfyUI listens on loopback only.
- No Hugging Face token is required for the selected public files.
- Downloads use HTTPS and verified SHA-256 values from the source repositories.
- The manifest records each model license and relevant use restriction.
- Generated images are local files and are not uploaded by the workflows.
- Juggernaut's model-specific paid API restriction will be called out in the
  comparison document even though local personal and creative use is allowed.

## Acceptance criteria

The installation is complete only when:

1. `verify.ps1` confirms a CUDA-enabled PyTorch build and reports the NVIDIA
   GeForce RTX 5060 Laptop GPU.
2. All selected model artifacts match their recorded SHA-256 digests.
3. ComfyUI responds successfully at `http://127.0.0.1:8188`.
4. Each of the six models generates a 1024-class square image at batch size one.
5. Each model also generates one landscape and one portrait image using the
   documented presets.
6. Required low-VRAM flags, if any, are recorded per model rather than hidden.
7. `MODEL_COMPARISON.md` contains source facts and measured local timing and
   peak-VRAM results, clearly distinguishing the two.
8. `README.md` gives direct setup, download, start, stop, verification, aspect
   ratio, and update instructions.
9. A fresh invocation of the setup and download scripts is idempotent and does
   not redownload or corrupt already-valid files.

