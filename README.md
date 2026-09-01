# godot-onnx-loader

[![CI](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml/badge.svg)](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DynamicDevices/godot-onnx-loader)](https://github.com/DynamicDevices/godot-onnx-loader/releases/latest)
[![Godot](https://img.shields.io/badge/Godot-4.6%2B-blue?logo=godotengine&logoColor=white)](https://godotengine.org/)

Godot **4.6+** GDExtension that runs **ONNX** models via Microsoft ONNX Runtime
1.20.1. Float tensors in/out only — no model-specific preprocessing.

Fork/refreshed from [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders).

## Build from source

The repository includes `godot-cpp` as a submodule. On Linux, this one command
fetches ONNX Runtime 1.20.1, builds the debug GDExtension, copies its runtime
libraries into the addon, and runs the Godot 4.6 smoke test:

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader
bash tools/godot_46_ms_ort.sh
```

The built addon is `addons/onnx_loader/`. Copy that whole directory into another
Godot project. For a manual or cross-platform build, initialize the submodule,
provide `ORT_ROOT` if automatic fetching is unsuitable, then run:

```bash
git submodule update --init --recursive
scons platform=linux target=template_debug # windows or macos also supported
```

Use `bash tools/godot_46_nix_store_ort.sh` on NixOS. See
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
and outputs. Integer/string tensors, sequences, maps, sparse tensors, and
unavailable execution providers fail explicitly.

On NixOS, native ORT profiling exposes the C++ allocator-boundary problem
documented elsewhere in this repository when the required
`ONNX_LOADER_SKIP_SESSION_RELEASE=1` workaround is active. The harness detects
that marker, so the demo uses its safe wall-time batch measurement instead. The native API stays
available for platforms that can release an ORT session normally. A host-level
trace check is also available in `tools/smoke_profile.c` for platform diagnosis.

From the repository root, open the demo in an installed Godot 4.6 editor with:

```bash
godot4 --editor --path demo
```

On NixOS, after `bash tools/godot_46_nix_store_ort.sh` has built and smoke-tested
the addon, launch the matching Godot 4.6 and ONNX Runtime environment with:

```bash
env ONNX_LOADER_SKIP_SESSION_RELEASE=1 \
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
| `*-assetlib.zip` | Linux + Windows + macOS (debug + release) + ORT |
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

The named API supports dense `float32` tensors of rank 0–8. Other ONNX element
types and value kinds (sequences, maps, optionals and sparse tensors) are outside
the current contract and fail explicitly rather than being silently coerced.

## Build and verification

**Linux** is the day-to-day path. **Windows / macOS** run host `smoke-csv` and
Godot 4.6 headless `csv_smoke` in CI on every PR.

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader

# Linux one-shot: fetch MS ORT, build, Godot 4.6 CSV smoke
bash tools/godot_46_ms_ort.sh
# → GODOT_46_MS_ORT_SMOKE_OK / GODOT_ONNX_CSV_SMOKE_OK
```

`scons` pulls Microsoft ORT automatically when needed and bundles it next to
the addon — you do not need to set `ORT_ROOT` for the happy path.

| Platform | Host smoke | Godot headless |
|----------|------------|----------------|
| Linux | `scons platform=linux … smoke-csv` | `godot_46_ms_ort.sh` / `godot_csv_smoke.sh` |
| Windows | `scons platform=windows … smoke-csv` | CI via `fetch_godot_46.sh` |
| macOS (arm64) | `scons platform=macos … smoke-csv` | CI via `fetch_godot_46.sh` |

Already built, with a Godot **4.6+** binary (`GODOT_BIN` / Downloads / `.godot-ci/`):

```bash
bash tools/godot_csv_smoke.sh   # refuses Godot < 4.6
```

Run `csv_smoke.tscn` explicitly in Godot 4.6+ for the automated fixture test.
Running the project normally opens the graphical named-tensor example.
(`demo/.godot/` is local cache; do not commit it.)

Host-only (no Godot): `scons smoke-csv`.

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

## License

MIT — see [LICENSE](LICENSE). Bundled `libonnxruntime` is Microsoft ONNX Runtime
(separate license; [onnxruntime.ai](https://onnxruntime.ai/)).

## Asset Library (maintainers)

Tag `vX.Y.Z` → release workflow attaches the AssetLib zip. Submit with
**Godot 4.6**, Download provider **Custom**, URL = the release asset (not a CI
artifact). Detail: [docs/ASSETLIB_SUBMIT_v0.2.0.md](docs/ASSETLIB_SUBMIT_v0.2.0.md).
