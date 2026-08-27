# godot-onnx-loader

Generic **ONNX Runtime GDExtension** for Godot 4.3 — mat490-style API, Linux/Nix/scons.

Fork/refreshed from [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders) with:

- C ORT API (not vendored Windows DLLs)
- `scons` build + Nix dev shell
- Float tensor in/out only — no model-specific preprocessing in the loader
- CSV smoke demo against the vizemes `ci-smoke` fixture (optional sidecar JSON for labels)

## API (`OnnxLoader`)

| Method | Description |
|--------|-------------|
| `load_model(onnx_path)` | Load `.onnx`; introspects input/output sizes |
| `predict(PackedFloat32Array)` | Raw float logits/outputs |
| `predict_array(Array)` | mat490-compatible `Array` wrapper |
| `get_input_size()` / `get_output_size()` | Flat element counts (batch=1) |

## Quick start

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader
nix develop   # MS ORT 1.20.1 prebuilt (NixOS-safe; nixpkgs libonnxruntime execstack fails in Godot)
scons platform=linux target=template_debug
scons smoke-csv   # host CSV table (no Godot required)
```

On NixOS, **do not** point `ORT_ROOT` at nixpkgs `onnxruntime` for Godot — the store
`libonnxruntime.so.1` requests an executable stack and Godot dlopen fails. The flake
and CI both use the Microsoft linux-x64 tarball instead.

`scons` copies `libonnxruntime.so.1` into `addons/onnx_loader/bin/`. The
GDExtension **dlopens** that copy at runtime (no link-time `NEEDED` on
`libonnxruntime`). After rebuild, check `get_diagnostics()["ort_library_path"]`
points at `.../addons/onnx_loader/bin/libonnxruntime.so.1`.

**NixOS Godot:** use the **official** Godot binary from `nix develop`
(`GODOT_BIN`). The nixpkgs `godot_4` wrapper aborts in ORT `ReleaseSession`
(`free(): invalid pointer`) on the same machine where official 4.5.1 is clean.

Godot 4.3 (optional):

```bash
# demo/addons/onnx_loader → ../../addons/onnx_loader (symlink)
open demo/ in Godot → run csv_smoke.tscn
# expect: GODOT_ONNX_CSV_SMOKE_OK
```

## Dev layout (vizemes-align sibling)

```text
~/work/godot-onnx-loader/          # this repo → builds addons/onnx_loader/
~/work/vizemes-align/
  godot-demo/
    addons/onnx_loader -> ../../godot-onnx-loader/addons/onnx_loader
```

Symlink for fast rebuild cycles; pin submodule/tag in vizemes when stable.

## Fixtures

`fixtures/ci-smoke/` — tiny viseme MLP ONNX + CSV probes (same numbers as
[vizemes-align](https://github.com/DynamicDevices/vizemes-align) `export/ci-smoke/`).
Demo applies **softmax in GDScript/C smoke**; the loader stays generic.

## License

MIT (loader code). ONNX fixtures are smoke-test artefacts from vizemes-align training.
