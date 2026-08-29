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
| `predict(PackedFloat32Array)` | Raw float logits/outputs |
| `predict_array(Array)` | mat490-compatible `Array` wrapper |
| `get_input_size()` / `get_output_size()` | Flat element counts (batch=1) |

## Build + smoke (Godot 4.6+)

**Target path today:** Linux x86_64 + Godot **≥ 4.6**. Windows/macOS CI builds
exist; full smoke/docs for those come when we ship them as first-class.

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader

# One-shot: fetch MS ORT, build addon, headless Godot 4.6 CSV smoke
bash tools/godot_46_ms_ort.sh
# → GODOT_46_MS_ORT_SMOKE_OK / GODOT_ONNX_CSV_SMOKE_OK
```

`scons` pulls Microsoft ORT automatically when needed and bundles
`libonnxruntime.so.1` next to the addon — you do not need to set `ORT_ROOT`
for the happy path.

Already built, with a Godot **4.6+** binary on `PATH` / `GODOT_BIN` /
`~/Downloads/Godot_v4.6*.x86_64`:

```bash
bash tools/godot_csv_smoke.sh   # refuses Godot < 4.6
```

Open `demo/` in Godot 4.6+ → `csv_smoke.tscn` → same OK token.
(`demo/.godot/` is local cache; do not commit it.)

Host-only (no Godot): `scons smoke-csv`.

### NixOS

Use the one-shot above from a **plain shell** (not `nix develop`’s Godot 4.5):

```bash
bash tools/godot_46_ms_ort.sh
```

That script handles MS ORT + `patchelf` for Godot’s FHS wrapper. Do not point
Godot 4.6 at the nixpkgs ORT from `nix develop`.

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
