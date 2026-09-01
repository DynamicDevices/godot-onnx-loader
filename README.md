# godot-onnx-loader

[![CI](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml/badge.svg)](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DynamicDevices/godot-onnx-loader)](https://github.com/DynamicDevices/godot-onnx-loader/releases/latest)
[![Godot](https://img.shields.io/badge/Godot-4.6%2B-blue?logo=godotengine&logoColor=white)](https://godotengine.org/)

Godot **4.6+** GDExtension that runs **ONNX** models via Microsoft ONNX Runtime
1.20.1. Float tensors in/out only — no model-specific preprocessing.

Fork/refreshed from [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders).

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
| `load_model(onnx_path)` | Load `.onnx`; introspects input/output sizes |
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

## Build + smoke (Godot 4.6+)

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

Open `demo/` in Godot 4.6+ → `csv_smoke.tscn` → same OK token.
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
