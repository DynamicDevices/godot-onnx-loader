# godot-onnx-loader

Generic **ONNX Runtime GDExtension** for Godot 4.5+ (mat490-style API).

Float tensors in/out only — no model-specific preprocessing. Linux/Nix/`scons`.

Fork/refreshed from [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders).

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
# Optional: nix develop   # flake.lock pins tool/ORT versions for Godot 4.5
scons platform=linux target=template_debug
scons smoke-csv                 # host CSV smoke (no Godot)
bash tools/godot_csv_smoke.sh   # Godot headless (set GODOT_BIN if needed)
```

If `ORT_ROOT` is unset, `scons` fetches Microsoft ONNX Runtime 1.20.1 into `/tmp`
and copies `libonnxruntime.so.1` into `addons/onnx_loader/bin/` (declared in the
`.gdextension` `[dependencies]` section for Godot export).

Open `demo/` in Godot 4.5+ → run `csv_smoke.tscn` → `GODOT_ONNX_CSV_SMOKE_OK`.
`demo/.godot/` stays local; smoke scripts recreate `extension_list.cfg` for headless.

### Godot 4.6 (Nix / FHS)

```bash
bash tools/godot_46_ms_ort.sh   # expect GODOT_46_MS_ORT_SMOKE_OK
```

Run from a plain shell (not inside `nix develop`). Uses MS ORT for build+runtime
and patchelf on Nix.

### Portable zip

```bash
bash tools/package_linux_portable.sh
# → /tmp/godot-onnx-loader-linux-x64-portable.zip
```

## Godot-shaped layout

```text
addons/onnx_loader/
  onnx_loader.gdextension   # relative [libraries] + [dependencies] (ORT)
  bin/                      # libonnx_loader*.so + libonnxruntime.so.1
  src/
demo/                       # thin consumer project (symlink to addon)
godot-cpp/                  # submodule, ABI-matched
```

The extension **dlopens** ORT (not linked `NEEDED`) so there is one ORT instance
process-wide. Godot still packs ORT via `[dependencies]` on export.

## Dev layout (vizemes-align sibling)

```text
godot-onnx-loader/addons/onnx_loader/
vizemes-align/godot-demo/addons/onnx_loader -> ../../godot-onnx-loader/addons/onnx_loader
```

## Fixtures

`fixtures/ci-smoke/` — tiny viseme MLP + CSV probes (same numbers as
[vizemes-align](https://github.com/DynamicDevices/vizemes-align) `export/ci-smoke/`).

## Known issues / ways forward

| Situation | What to do |
|-----------|------------|
| Ubuntu / generic Linux | Quick start (bundled MS ORT) |
| `nix develop` + Godot 4.5 | Store ORT via `ONNX_ORT_BIN`; `godot_csv_smoke.sh` |
| Godot 4.6 FHS on Nix | `bash tools/godot_46_ms_ort.sh` |
| `resolve_bundled_ort_path` / missing `.so` | Ensure `addons/onnx_loader/bin/libonnxruntime.so.1` or set `ONNX_ORT_BIN` |
| `cannot enable executable stack` on dlopen | glibc 2.41+ rejects RWE stacks; `clear_ort_execstack.py` runs on bundle / `godot_46_ms_ort.sh` |

`ONNX_LOADER_SKIP_SESSION_RELEASE` defaults **on** (skips session+env release under
Godot 4.6 teardown). Set `=0` only when testing ORT teardown deliberately.

Longer term: build ORT from source (submodule) if you need a fully controlled ABI.

## License

MIT (loader code). ONNX fixtures are smoke-test artefacts from vizemes-align training.
