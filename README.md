# godot-onnx-loader

[![CI](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml/badge.svg)](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DynamicDevices/godot-onnx-loader)](https://github.com/DynamicDevices/godot-onnx-loader/releases/latest)
[![Godot](https://img.shields.io/badge/Godot-4.6%2B-blue?logo=godotengine&logoColor=white)](https://godotengine.org/)

Godot **4.6+** GDExtension that runs **ONNX** models via ONNX Runtime. Release
builds pin ORT **1.22.2** at commit `5630b081cd25e4eccc7516a652ff956e51676794`.
The stable public API currently accepts dense float32 tensors only; it performs
no model-specific preprocessing.

Fork/refreshed from [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders).

## Build from source

The repository includes `godot-cpp` as a submodule. The reproducible source path
checks out the exact ORT commit above, builds a CPU-only shared runtime, and
stages it as `ORT_ROOT`:

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader
bash tools/build_ort_from_source.sh
ORT_ROOT="$PWD/.ort-source-install" ORT_BUNDLE=1 \
  scons platform=linux target=template_debug smoke-csv stress-sessions
```

The built addon is `addons/onnx_loader/`. Copy that whole directory into another
Godot project. For a manual or cross-platform build, initialize the submodule,
provide `ORT_ROOT` if automatic fetching is unsuitable, then run:

```bash
git submodule update --init --recursive
scons platform=linux target=template_debug # windows or macos also supported
```

Use `bash tools/godot_46_nix_store_ort.sh` on NixOS; it runs the complete native
and Godot lifecycle suite against a single pinned nixpkgs compiler/runtime set.
On Windows, `tools/bootstrap_windows_android.ps1` installs/verifies the Android
toolchain and `tools/build_android_source_windows.ps1` builds ORT and the
extension from source, exports an APK, installs it, and requires on-device
inference and teardown markers. See
[Build and verification](#build-and-verification) for smoke tests, platform
coverage, and release packaging.

## Use it from Godot

Put the model inside the Godot project and instantiate `OnnxLoader` directly;
there is no autoload or scene node to configure. This example exercises the new
named multi-input/multi-output API:

```gdscript
var model := OnnxLoader.new()
assert(model.load_model("res://models/matrix_vector.onnx"))

var matrix := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8])
var vector := PackedFloat32Array([10, 20, 30])
assert(model.set_input("matrix", matrix, PackedInt64Array([4, 2])))
assert(model.set_input("vector", vector, PackedInt64Array([3])))
assert(model.run(PackedStringArray(["output"])))
var output: PackedFloat32Array = model.get_output("output") # [76, 80]
```

Use `get_input_descriptors()` and `get_output_descriptors()` when input names or
shapes are not known in advance. Always check the Boolean result of
`load_model()`, `set_input()`, and `run()`; `get_last_error()` explains a failed
named operation.

## Graphical named-API example

Open `demo/project.godot` in Godot 4.6+ and run the project. The scene owns the
model selector, scroll areas, Run/Benchmark controls, timing, and log. After a
model loads, the script introspects its names and shapes and generates only the
model-dependent `SpinBox` tables. Edit dynamic dimensions, press **Apply Shape**,
enter values, and run an individual trial. The output tables use the actual
names and shapes returned by ONNX Runtime. A separate metadata panel displays
the model's ONNX `metadata_props`, or clearly reports that none are present.

ONNX reports a dynamic dimension as `-1`; for example `[-1,1600]` commonly
means a runtime-selected batch size followed by 1,600 features. The inspector
initializes dynamic dimensions to `1`, so a one-item trial becomes `[1,1600]`.
Tensors of up to 512 values use indexed spin boxes. Larger tensors use a
pasteable whitespace/comma-separated text field (with a zero-fill shortcut), so
the display limit never prevents binding the complete tensor.

The included `demo/models/matrix_vector.onnx` model is intentionally explicit:

```text
matrix: float32[4,2]    vector: float32[3]    output: float32[2]
output = reduce_sum(matrix, axis=0) + reduce_sum(vector)
```

With each input table automatically initialized to `1, 2, 3…`, its output is
`[22, 26]`.
Change **Model Path** to point at another dense-float32 ONNX model. The static
application structure lives in `demo/matrix_demo.tscn`; `demo/matrix_demo.gd`
contains the ONNX calls and the small tensor-table factory.
The model's purpose, complete calculation, and adaptation intent are documented
in the module docstrings of `demo/matrix_demo.gd` and
`tools/make_matrix_fixture.py`, keeping explanatory prose out of the running UI.

The loader supports dense `float32` tensors of rank 0–8 and at most 32 inputs
and outputs. Float16, float64, int32, int64, and bool identity fixtures are
tested and rejected during load with the exact ONNX element type and the
message `only float32 is supported`; they are not silently converted. Strings,
sequences, maps, sparse tensors, and unavailable execution providers likewise
remain outside the current contract. Typed Godot APIs are deferred until their
copying/coercion semantics can be added without weakening the existing float32
API.

### Game-runtime CPU policy

ONNX Runtime normally creates a parallel CPU worker pool whose threads may spin
between calls to minimize batch-inference latency. That default is unsuitable
for a game process making small periodic inferences: idle workers can occupy
many cores even when each `run()` takes less than a millisecond.

The loader therefore creates CPU sessions with one intra-operation thread,
sequential execution, and intra/inter-operation spinning disabled. This keeps
inference on the calling thread and allows the CPU to sleep between calls.
Applications should move periodic inference to their own worker thread only
when its measured call latency is too large for their frame budget; doing so is
not required to prevent ONNX Runtime from occupying idle cores.

`OrtSession` and `OrtEnv` are destroyed normally. `ONNX_LOADER_SKIP_SESSION_RELEASE=1`
is a diagnostic escape hatch only and leaks by design; never use it in a release.

The teardown failure had a loader/symbol-scope cause. A native C host could
create and destroy repeated sessions, while Godot aborted with `free(): invalid
pointer` on the second in-process model replacement. A matched Nix compiler and
shared C++ runtime removed one ABI variable but the two-live-model reproducer
still failed. The decisive A/B was removing Linux `RTLD_DEEPBIND`: with normal
`RTLD_NOW | RTLD_LOCAL` resolution, the same Godot process passes repeated
`ReleaseSession`, shared-`OrtEnv` lifetimes, and editor shutdown. Deep binding
had split symbol resolution across Godot and ORT's dependency graph, violating
the allocator ownership expected by ORT's C++ implementation. The extension
also never embeds a second static libstdc++/libgcc on Linux.

From the repository root, open the demo in an installed Godot 4.6 editor with:

```bash
godot4 --editor --path demo
```

On NixOS, after `bash tools/godot_46_nix_store_ort.sh` has built and smoke-tested
the addon, launch the matching Godot 4.6 and ONNX Runtime environment with:

```bash
nix shell github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#godot_4_6 \
  github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41#onnxruntime \
  --command godot4 --editor --path demo
```

Press **F6** to run the open scene or **F5** to run the demo project.

For an independent NixOS smoke test from a fresh clone, the complete sequence is:

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader
bash tools/godot_46_nix_store_ort.sh
```

The final command must print `GODOT_46_NIX_STORE_ORT_SMOKE_OK`. Then use the
editor-launch command above to inspect the interactive graph.

The fixture is checked in so the demo works offline. To regenerate it after
editing its graph, install Python's `onnx` package and run:

```bash
python3 tools/make_matrix_fixture.py
```

## Install

Download a zip from the
[latest release](https://github.com/DynamicDevices/godot-onnx-loader/releases/latest),
unzip, copy `addons/onnx_loader/` into your project.

| Zip | Contents |
|-----|----------|
| `*-assetlib.zip` | Linux + Windows + macOS arm64 + Android arm64 (debug + release) + ORT |
| `*-linux-x86_64.zip` | Linux only (smaller) |

ORT loads from the addon’s own `bin/` (no env vars for normal use).

## API (`OnnxLoader`)

| Method | Description |
|--------|-------------|
| `load_model(onnx_path)` | Load `.onnx` from `res://`, `user://`, or an OS path; introspects its I/O |
| `predict(PackedFloat32Array)` | Raw float logits/outputs (fixed flat `[1,N]`) |
| `predict_shaped(data, shape)` | Dynamic-time models (e.g. TCN `[1,T,F]`) |
| `predict_array(Array)` | mat490-compatible `Array` wrapper |
| `get_input_size()` / `get_output_size()` | Flat counts, or `-1` when a non-batch dim is dynamic |
| `get_model_metadata()` / `get_metadata_value(key)` | ONNX `metadata_props` |
| `get_input_descriptors()` / `get_output_descriptors()` | Named float32 tensor contracts: name, rank, shape and flat size |
| `set_input(name, data, shape)` | Persistently bind or replace a named input tensor |
| `run(output_names = [])` | Run using all bound inputs; empty selects every output |
| `get_output(name)` / `get_output_shape(name)` | Read a selected output from the latest successful run |
| `get_output_scalar(name, index)` / `get_output_slice(name, offset, count)` | Convenience accessors for a latest-run output |
| `get_run_generation()` / `get_last_error()` | Detect fresh output and diagnose validation/run failures |
| `load_model_profiled(path, prefix)` | Load a model with ONNX Runtime JSON event tracing enabled |
| `end_profiling()` | Stop tracing and return the generated JSON path |

Named inputs start **unbound** after `load_model()`. Every required input must be
set before `run()`; a zero-filled tensor is a real bound value, not a missing
input. Bind slow-changing inputs only when they change:

```gdscript
var loader := OnnxLoader.new()
assert(loader.load_model("res://model.onnx"))
loader.set_input("speaker_context", speaker_features, PackedInt64Array([1, 6]))
loader.set_input("mel", mel_window, PackedInt64Array([1, hops, 80]))
assert(loader.run(PackedStringArray(["vad"])))
var vad := loader.get_output_scalar("vad")
```

Selected outputs remain native-side until a getter copies them into Godot. A
run attempt invalidates the previous output set; success installs fresh outputs
and increments the generation, while failure leaves no retrievable output.
Requesting another output later requires another run.

`set_input()` reuses its ORT tensor when the name, type and concrete shape are
unchanged, copying only new values. `get_diagnostics()` reports
`input_tensor_allocations` and `input_tensor_reuses`, plus the loader compiler,
C++ runtime, runtime-reported ORT version/path, CPU execution provider, thread
counts, execution mode, spinning policy, and graph optimization level.

### Thread ownership

An `OnnxLoader` has one mutable input/output cache and must have one exclusive
owner at a time. It may be created, loaded and used on a worker thread, but do
not call one instance concurrently or unload it while a run is active. Different
fully constructed instances may run concurrently. Serialize creation/destruction
until the shared ORT environment receives an explicit lock.

The named API supports dense `float32` tensors of rank 0–8. Other ONNX element
types and value kinds (sequences, maps, optionals and sparse tensors) are outside
the current contract and fail explicitly rather than being silently coerced.

### Model contract metadata

Tensor descriptors define syntax, not meaning. Producers should add
`onnx_loader.contract_version=1` plus metadata (or a sidecar
`<model>.manifest.json`) describing every input/output's axis order, units,
normalization, feature ordering and applicable sample/frame rate. The loader
exposes metadata unchanged; model-specific preprocessing remains application code.

Use these repeatable keys, substituting the exact ONNX tensor name:

| Key | Example |
|-----|---------|
| `onnx_loader.contract_version` | `1` |
| `onnx_loader.input.<name>.axes` | `batch,time,feature` |
| `onnx_loader.input.<name>.units` | `unitless_rotation_like_features` |
| `onnx_loader.input.<name>.normalization` | `mean/std sidecar-v1` |
| `onnx_loader.input.<name>.feature_order` | `documented producer ordering` |
| `onnx_loader.input.<name>.sample_rate_hz` / `frame_rate_hz` | `16000` / `30` |
| `onnx_loader.output.<name>.axes` | `batch,feature` |
| `onnx_loader.output.<name>.units` | `logits`, `radians`, etc. |
| `onnx_loader.output.<name>.feature_order` | `documented consumer ordering` |

`fixtures/hardening/temporal_pose.onnx` is a generated, redistributable example:
dynamic `[1,time,36]` input, tested at `[1,40,36]`, with `[1,135]` output and
the metadata schema above. It contains only `Flatten`/`Slice`, not trained weights.

## Build and verification

The source-build workflow compiles pinned ORT plus the GDExtension on Linux
x86-64, Windows x86-64, macOS arm64, and Android arm64. Desktop jobs run actual
Godot 4.6 load/inference/replacement/teardown; Android CI compiles artifacts,
while the physical-device test is run from the Windows script.

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader

# Pinned source ORT + extension + host suites
bash tools/build_ort_from_source.sh
ORT_ROOT="$PWD/.ort-source-install" ORT_BUNDLE=1 scons \
  smoke-csv stress-sessions smoke-temporal-fixture smoke-type-rejections \
  smoke-load-failures smoke-shape-edges benchmark-inference
```

Bare `scons` retains the legacy Microsoft-binary fallback for developer
convenience. Release artifacts and the `source-ort` workflow use the pinned
source path instead.

| Platform | Current status | Evidence |
|----------|----------------|----------|
| Linux x86-64, NixOS | Supported with pinned Nix-native ORT | Godot 4.6 two-live-model/replacement/teardown; 50-session native stress |
| Linux x86-64, glibc distro | Experimental package | Source-build workflow and desktop runtime suite configured; release CI must pass |
| Windows x86-64 | Experimental | Existing Godot headless CI; pinned source-build/runtime workflow configured but not yet green on this branch |
| macOS arm64 | Experimental | Pinned source-build/runtime workflow configured but not yet green on this branch |
| macOS x86-64/universal | Unsupported | Not packaged/tested |
| Android arm64 | Experimental | Source-built ORT + extension; Godot 4.6.1 APK passed 8 sessions/512 runs on OnePlus 8 (Android 13) |
| Standalone Quest | Experimental/unverified | Same arm64 target compiles; no completed Quest runtime inference yet |
| Web / HTML5 | Unsupported design target | Current native loader uses `dlopen`/`LoadLibrary`; needs a wasm ORT build and Godot Web integration |
| iOS | Unsupported | Not packaged/tested |

Already built, with a Godot **4.6+** binary (`GODOT_BIN` / Downloads / `.godot-ci/`):

```bash
bash tools/godot_csv_smoke.sh   # refuses Godot < 4.6
```

Run `csv_smoke.tscn` explicitly in Godot 4.6+ for the automated fixture test.
Running the project normally opens the graphical named-tensor example.
(`demo/.godot/` is local cache; do not commit it.)

Host-only (no Godot): use the SCons aliases shown above.

On the current pinned Nix/ORT 1.22.2 run, 25 pairs of simultaneously live
sessions (50 lifetimes, 5,000 inferences) completed with 15,544 KiB cold-start
RSS growth and **0 KiB steady-state growth after five pairs**. The Godot-hosted
suite separately completed 1,000 inferences, four model replacements, and clean
shutdown with two loaders alive.

The input-reuse benchmark used the same compiler, ORT, model, 100 warm-ups and
10,000 measured inferences for five runs. Median CPU time changed from
15.511 us/inference to 13.702 us/inference (11.7% lower). More importantly,
input `OrtValue` allocations changed from **10,100 to 1**, with 10,099 in-place
copies/reuses. Timing is fixture/host-specific; the allocation count is the
contract enforced by CI.

### Release recommendation

Target `v0.4.0` after the newly configured pinned-source Windows, macOS, Linux,
and Android release jobs pass and their merged Asset Library zip is inspected.
Do not call the release generic across all platforms: Android remains
experimental, Quest still needs a packaged runtime test, and Web/iOS are not
implemented.

As checked on 2026-09-25, searches of the official Godot Asset Library did not
return this plugin; GitHub releases alone do not establish an Asset Library
listing. Treat submission as still outstanding and verify the eventual public
asset URL before claiming availability.

### NixOS

Use the Nix-native one-shot from a **plain shell**:

```bash
bash tools/godot_46_nix_store_ort.sh
```

That script builds against and runs with one exact nixpkgs ORT store output. It
uses a store-ORT-specific SCons cache namespace so bundled MS ORT artifacts
cannot be restored into the build.

### Package a release zip

```bash
bash tools/package_assetlib.sh
```

Tagged pushes run `release.yml` and attach zips to the GitHub Release.

## Layout

```text
addons/onnx_loader/   # ship unit (.gdextension + bin/ + ORT)
demo/                 # headless / editor smoke project
src/                  # GDExtension sources (not in the ship zip)
godot-cpp/            # submodule
tools/                # smoke + package scripts
```

## AI-assisted development disclosure

This project uses AI coding assistants, including OpenAI Codex, during design,
implementation, debugging, test development, and documentation. AI-produced
suggestions are treated as untrusted contributions: maintainers review the
changes, run the documented native and Godot test suites, and remain responsible
for the code and releases. The repository history, tests, CI results, and known
platform limitations are kept visible so users can evaluate the software on its
technical evidence rather than on how individual edits were drafted.

## License

MIT — see [LICENSE](LICENSE). Bundled `libonnxruntime` is Microsoft ONNX Runtime;
release zips include its separate MIT license as
`addons/onnx_loader/LICENSE.onnxruntime`.

## Asset Library (maintainers)

Tag `vX.Y.Z` → release workflow attaches the AssetLib zip. Submit with
**Godot 4.6**, Download provider **Custom**, URL = the release asset (not a CI
artifact). Detail: [docs/ASSETLIB_SUBMIT_v0.2.0.md](docs/ASSETLIB_SUBMIT_v0.2.0.md).
