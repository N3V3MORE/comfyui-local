# Six-model comparison

Measured locally on 21 July 2026 with an NVIDIA GeForce RTX 5060 Laptop GPU (8,151 MiB reported), Ryzen AI 7 350, 31.3 GB RAM, Windows 11, ComfyUI `d0fec2e`, Torch 2.11 CUDA 13, and seed `20260721`.

Each average covers one square 1024×1024, one landscape 1216×832, and one portrait 832×1216 image. Time is end-to-end prompt wall time. Peak VRAM is the maximum total GPU memory observed by `nvidia-smi`; it includes ComfyUI and the display stack, so compare it as a practical system peak rather than checkpoint size.

| Model | Focus | Architecture | Installed precision | Payload | Steps | Avg time | Peak VRAM | License/model card |
|---|---|---|---|---:|---:|---:|---:|---|
| RealVisXL V5.0 | Natural realism | SDXL, ~2.6B | FP16 | 6.94 GB | 30 | 18.91 s | 7,726 MiB | [OpenRAIL++](https://huggingface.co/SG161222/RealVisXL_V5.0) |
| Juggernaut XL v9 | Cinematic realism | SDXL, ~2.6B | FP16 | 7.11 GB | 35 | 21.71 s | 7,409 MiB | [CreativeML Open RAIL-M; card restrictions apply](https://huggingface.co/RunDiffusion/Juggernaut-XL-v9) |
| Animagine XL 4.0 Opt | Detailed anime | SDXL, ~2.6B | FP16 | 6.94 GB | 28 | 18.18 s | 7,475 MiB | [OpenRAIL++](https://huggingface.co/cagliostrolab/animagine-xl-4.0) |
| Illustrious XL v2.0 | Clean illustrative anime | SDXL, ~2.6B | FP16 | 6.94 GB | 30 | 19.64 s | 7,440 MiB | [CreativeML Open RAIL-M](https://huggingface.co/OnomaAIResearch/Illustrious-XL-v2.0) |
| Z-Image Turbo | Facial photorealism | S3-DiT, 6B | NVFP4 diffusion + FP4-mixed text | 8.32 GB | 8 | 9.27 s | 7,605 MiB | [Apache-2.0](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo) |
| FLUX.2 Klein 4B | Fast photo generation | Rectified-flow transformer, 4B | FP8 diffusion + FP4 text | 8.26 GB | 4 | 5.23 s | 7,640 MiB | [Apache-2.0](https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8) |

Payload includes every file needed by that model. Z-Image and FLUX.2 therefore include their diffusion model, text encoder, and VAE, while each SDXL entry is a self-contained checkpoint.

## Which one to use

| Need | First choice | Why |
|---|---|---|
| Natural people and everyday photography | RealVisXL V5.0 | The most restrained, documentary-looking SDXL result in the proof set. |
| Dramatic lighting and cinematic scenes | Juggernaut XL v9 | Strong contrast, colour, atmosphere, and composition; slowest here because it uses 35 steps. |
| Rich, polished anime character art | Animagine XL 4.0 Opt | Strong detail and lighting with tag-style prompts. |
| Softer, cleaner illustration | Illustrious XL v2.0 | A visibly different anime baseline with simpler line and colour treatment. |
| Best photorealistic faces | Z-Image Turbo | Strong skin, hair, and background detail in eight steps; bilingual text is also a documented strength. |
| Fast iteration and previews | FLUX.2 Klein 4B | Fastest measured model by a wide margin at four steps, with convincing photographic texture. |

Z-Image's official guide describes a 6B single-stream architecture and eight-function-evaluation Turbo workflow. The official [Z-Image ComfyUI guide](https://docs.comfy.org/tutorials/image/z-image/z-image-turbo) uses separate diffusion, Qwen, and VAE files. FLUX.2 Klein is the distilled four-step 4B variant from the official [ComfyUI Klein guide](https://docs.comfy.org/tutorials/flux/flux-2-klein).

## 8 GB findings

- All six models completed all three orientations without an out-of-memory error.
- Observed peaks ranged from 7,409 to 7,726 MiB; close other GPU-heavy programs before generating.
- The default dynamic-VRAM/offload behaviour worked. ComfyUI's maintainer describes it as the default path for memory-constrained NVIDIA systems, with higher apparent VRAM use being normal: [dynamic VRAM announcement and discussion](https://github.com/Comfy-Org/ComfyUI/discussions/12699).
- FP8/FP4 modern-model artifacts were chosen because full-weight modern models are poor fits for 8 GB. Earlier community tests also show low-VRAM systems benefiting from reduced precision, though those results are hardware-specific: [ComfyUI FP8 discussion](https://github.com/Comfy-Org/ComfyUI/discussions/2180).
- Start with the supplied presets. Larger canvases can work, but memory and generation time rise, and they are outside this verified matrix.

## Per-orientation measurements

| Model | Square | Landscape | Portrait |
|---|---:|---:|---:|
| RealVisXL V5.0 | 21.64 s / 7,365 MiB | 17.70 s / 6,516 MiB | 17.38 s / 7,726 MiB |
| Juggernaut XL v9 | 23.97 s / 7,409 MiB | 20.48 s / 6,533 MiB | 20.68 s / 6,557 MiB |
| Animagine XL 4.0 Opt | 20.48 s / 7,475 MiB | 17.05 s / 6,535 MiB | 17.01 s / 6,538 MiB |
| Illustrious XL v2.0 | 21.57 s / 7,440 MiB | 18.43 s / 6,447 MiB | 18.92 s / 6,432 MiB |
| Z-Image Turbo | 12.39 s / 7,605 MiB | 7.71 s / 6,036 MiB | 7.70 s / 6,003 MiB |
| FLUX.2 Klein 4B | 6.87 s / 7,640 MiB | 4.66 s / 5,615 MiB | 4.15 s / 5,620 MiB |

These figures compare the tested workflows, not architecture alone: prompts, samplers, and step counts intentionally follow each model's recommended operating style.

## License note

The six files do not share one license. Apache-2.0, OpenRAIL++, and CreativeML Open RAIL-M have different terms, and individual model cards can add usage or hosted-service restrictions. Check the linked card for the exact model before redistribution, paid API use, or commercial deployment.
