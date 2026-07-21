# Semantic Workflow Compiler Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace numeric-node-ID workflow mutation and the monolithic PowerShell app generator with one tested Python compiler that uses semantic keys and produces the existing UI, App Mode, and API artifacts without changing the 15-app user experience.

**Architecture:** Windows-facing PowerShell remains responsible for environment setup, process launch, and calling the compiler. `src/comfy_local` owns manifest loading, semantic selection, graph construction, validation, compilation, installation, and benchmark prompt materialization. Declarative workflow specifications select stable `studio_key` values; numeric node and link IDs exist only in serialized ComfyUI JSON.

**Tech Stack:** Python 3.13 standard library (`dataclasses`, `json`, `pathlib`, `unittest`), PowerShell 7/Windows PowerShell entrypoints, ComfyUI workflow JSON 0.4, JSON Schema-compatible configuration.

## Global Constraints

- Preserve all six core models, 15 App Mode workflows, seven 8 GB-safe resolutions, five pinned extensions, and 11 support assets.
- Never mix SDXL, Z-Image, and FLUX.2 components or LoRAs.
- Do not load model weights in unit or snapshot tests.
- Keep generated workflows deterministic and reviewable.
- Do not add a distributable CLI framework, video workflows, or new models in this refactor.
- Use a failing test before every production-code change.

---

### Task 1: Characterization snapshots and isolated workspace

**Files:**
- Create: `tests/snapshots/apps/*.json`
- Create: `tests/snapshots/ui/*.json`
- Create: `tests/snapshots/api/*.json`
- Create: `tests/unit/test_snapshots.py`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: current committed files under `workflows/apps`, `workflows/ui`, and `workflows/api`.
- Produces: `normalize_workflow(value: object) -> object` and deterministic baseline snapshots.

- [ ] Add a failing snapshot test that imports `comfy_local.normalization.normalize_workflow` and compares every current workflow with a normalized snapshot.
- [ ] Run `.venv\Scripts\python.exe -m unittest discover -s tests\unit -p "test_*.py" -v`; expect import failure for `comfy_local.normalization`.
- [ ] Implement normalization that removes canvas-only `pos`, `size`, `groups`, and `extra.ds` fields while retaining node IDs, links, widgets, semantic properties, and App Mode metadata.
- [ ] Generate the initial snapshots from the committed workflows and rerun the test; expect all comparisons to pass.
- [ ] Run `tests\run-tests.ps1`; expect the existing 50 tests plus the snapshot bridge to pass.

### Task 2: Typed manifests and semantic graph selectors

**Files:**
- Create: `src/comfy_local/__init__.py`
- Create: `src/comfy_local/manifests.py`
- Create: `src/comfy_local/graph.py`
- Create: `src/comfy_local/selectors.py`
- Create: `src/comfy_local/validation.py`
- Create: `tests/unit/test_selectors.py`
- Create: `tests/unit/test_validation.py`

**Interfaces:**
- Produces: `WorkflowGraph.from_ui_json(data)`, `WorkflowGraph.find_one(*, studio_key=None, node_type=None, title=None)`, `validate_ui_graph(graph)`, and `ValidationError`.
- Semantic identity is read from `node.properties.studio_key`.

- [ ] Write failing tests for one semantic match, zero matches, duplicate matches, duplicate `studio_key` values, missing link endpoints, nonexistent App Mode widgets, nonexistent output nodes, inconsistent `last_node_id`/`last_link_id`, and absolute paths.
- [ ] Run the focused unit tests and verify failures are caused by missing graph APIs.
- [ ] Implement immutable manifest dataclasses and exact-one selectors with useful error messages.
- [ ] Implement structural validation for root nodes, subgraph nodes, links, App Mode tuples, output nodes, and approved relative model paths.
- [ ] Rerun focused tests and the complete suite.

### Task 3: Declarative configuration and one source of truth

**Files:**
- Create: `config/models.json`
- Create: `config/artifacts.json`
- Create: `config/benchmark-scenarios.json`
- Create: `config/workflow-specs.json`
- Create: `config/licenses.json`
- Rename: `config/aspect-ratios.json` to `config/resolutions.json`
- Modify: `custom_nodes/comfyui_local_studio/presets.py`
- Create: `tests/unit/test_manifests.py`
- Modify: `tests/studio_nodes_test.py`

**Interfaces:**
- `load_models(root) -> dict[str, ModelProfile]`
- `load_workflow_specs(root) -> tuple[WorkflowSpec, ...]`
- `load_resolutions(path) -> dict[str, tuple[int, int]]`
- `WorkflowSpec.exposed_inputs` contains semantic node keys and widget names.

- [ ] Write failing tests that require unique model/spec/artifact IDs, valid family membership, declared artifacts for every component, resolvable model profiles, resolvable support assets, and seven resolutions loaded from JSON.
- [ ] Split the existing manifest data without changing values or download hashes.
- [ ] Make the custom node locate `config/resolutions.json` through `COMFYUI_LOCAL_CONFIG`, falling back to the repository-relative path used by the linked local package.
- [ ] Update downloader, verifier, and tests to consume focused manifests through compatibility loaders; remove duplicate resolution literals.
- [ ] Run focused and full tests.

### Task 4: Semantic canonical templates and graph builder

**Files:**
- Create: `vendor/workflows/sdxl-base.json`
- Create: `vendor/workflows/z-image-turbo.json`
- Create: `vendor/workflows/flux2-klein.json`
- Create: `vendor/workflows/ipadapter-sdxl.json`
- Create: `vendor/workflows/face-detailer-sdxl.json`
- Create: `src/comfy_local/builder.py`
- Create: `src/comfy_local/templates.py`
- Create: `tests/unit/test_builder.py`

**Interfaces:**
- `GraphBuilder.add(node_type, *, key, widgets, inputs) -> NodeHandle`
- `NodeHandle.output(name) -> OutputHandle`
- `GraphBuilder.to_ui_workflow() -> dict`
- `load_template(path) -> WorkflowGraph`

- [ ] Write failing tests proving handles create valid links, IDs are allocated only during serialization, duplicate keys fail, and selectors resolve every required canonical template key exactly once.
- [ ] Vendor the current pinned upstream templates and add stable keys such as `checkpoint`, `positive_prompt`, `negative_prompt`, `latent`, `sampler`, `save_image`, `width`, `height`, and `seed`.
- [ ] Implement the builder and template loader without embedding model-specific data.
- [ ] Validate all vendored templates and run snapshots.

### Task 5: One compiler for UI, App Mode, and API artifacts

**Files:**
- Create: `src/comfy_local/compiler.py`
- Create: `src/comfy_local/app_mode.py`
- Create: `src/comfy_local/api_prompt.py`
- Create: `src/comfy_local/cli.py`
- Create: `tests/unit/test_compiler.py`
- Create: `tests/integration/test_compile_catalog.py`

**Interfaces:**
- `compile_catalog(root: Path, output_root: Path) -> CompileResult`
- `compile_spec(spec, models, templates) -> CompiledWorkflow`
- `CompiledWorkflow.ui`, `.app`, and `.api_prompt` share model, sampler, prompt, seed, and dimensions.
- `python -m comfy_local compile --root <path> --output-root <path>` compiles deterministically.

- [ ] Write failing tests for SDXL Photo/Anime, Z-Image, and FLUX.2 model-family compilation, semantic App Mode input resolution, deterministic output, and shared sampler/model values across serializers.
- [ ] Implement SDXL compilation first and compare normalized output with the four Create SDXL snapshots.
- [ ] Implement Z-Image and FLUX.2 compilation using semantic subgraph keys; no compiler code may refer to numeric IDs.
- [ ] Implement reusable Canny, Depth, Pose, IPAdapter, FaceDetailer, and Upscale variants with builder handles.
- [ ] Compile all 15 apps, four editable base UI workflows, and three family API prompts; validate every artifact before writing it atomically.
- [ ] Run unit, snapshot, catalog integration, and complete tests.

### Task 6: Thin PowerShell boundaries and installation separation

**Files:**
- Create: `scripts/compile.ps1`
- Create: `scripts/install-workflows.ps1`
- Create: `scripts/copy-bundled-inputs.ps1`
- Replace: `scripts/sync-studio-apps.ps1`
- Replace: `scripts/sync-workflows.ps1`
- Modify: `scripts/setup.ps1`
- Modify: `tests/setup.tests.ps1`
- Modify: `tests/apps.tests.ps1`

**Interfaces:**
- `compile.ps1` calls `python -m comfy_local compile` and contains no ComfyUI node types or IDs.
- `install-workflows.ps1` copies already-validated outputs according to `workflow-specs.json`.
- `copy-bundled-inputs.ps1` copies only declared bundled input assets.
- `sync-studio-apps.ps1` remains a compatibility wrapper that calls the three focused scripts.

- [ ] Write failing source-boundary tests that reject node type names, numeric App Mode IDs, inline link arrays, JSON mutation helpers, and asset copying in the compatibility wrapper.
- [ ] Implement the three focused wrappers and reduce both old sync scripts to compatibility entrypoints.
- [ ] Update setup to compile, copy assets, then install in explicit order.
- [ ] Run all PowerShell and Python tests.

### Task 7: Specification-driven verification and benchmarking

**Files:**
- Create: `src/comfy_local/benchmark.py`
- Modify: `scripts/benchmark.ps1`
- Modify: `scripts/verify.ps1`
- Modify: `tests/benchmark.tests.ps1`
- Modify: `tests/runtime.tests.ps1`

**Interfaces:**
- `materialize_benchmark_prompt(model_id, scenario_id, seed, dimensions) -> dict`
- Verification derives expected UI/app/artifact counts and required node types from focused manifests.
- PowerShell benchmark code keeps GPU monitoring, HTTP submission, waiting, and result copying only.

- [ ] Write failing tests proving expected counts are derived, benchmark mutation has no family switch, and compatible models receive shared performance/quality scenarios.
- [ ] Implement performance scenarios with cold/warm metadata, three repeat seeds, and shared prompts by compatible family.
- [ ] Implement quality scenarios for photography, anime, composition, hands/faces, embedded text, and prompt adherence without running them by default.
- [ ] Replace family-specific PowerShell prompt mutation with the Python materializer.
- [ ] Run unit and full tests; preserve existing benchmark result fields for backward compatibility.

### Task 8: Live integration, documentation, and completion

**Files:**
- Modify: `README.md`
- Modify: `MODEL_COMPARISON.md`
- Modify: `docs/evidence/benchmark-summary.json` only if benchmark schema documentation requires it.

**Interfaces:**
- Existing commands remain valid; `scripts/compile.ps1` is the documented compiler entrypoint.

- [ ] Compile into a temporary directory and prove byte-for-byte deterministic output across two runs.
- [ ] Run all unit, snapshot, PowerShell, and integration tests.
- [ ] Install compiled workflows, restart ComfyUI if required, query `/object_info`, verify all compiled node types, verify all App Mode files are served, and submit representative tiny prompts without re-running the full 18-image GPU benchmark unless graph behavior changed materially.
- [ ] Run full artifact/hash verification and `git diff --check`.
- [ ] Update documentation with the compiler architecture, configuration ownership, extension points, and migration notes.
- [ ] Use `superpowers:finishing-a-development-branch`, verify the final suite, and present merge/push/keep/discard options.
