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

## Quick start (recommended)

One path for a fresh clone. If `ORT_ROOT` is unset, `scons` fetches Microsoft
ONNX Runtime 1.20.1 into `/tmp` automatically.

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader
# Optional Nix shell (pins tool versions via flake.lock):
#   nix develop
scons platform=linux target=template_debug
scons smoke-csv          # host CSV smoke (no Godot)
bash tools/godot_csv_smoke.sh   # Godot 4.5 headless, if GODOT_BIN is set
```

Open `demo/` in Godot 4.5+ and run `csv_smoke.tscn` — expect `GODOT_ONNX_CSV_SMOKE_OK`.
(`demo/.godot/` is local-only; the smoke scripts recreate `extension_list.cfg` so headless
CI does not need it committed.)

### Godot 4.6 (one command)

On NixOS / when the Godot 4.6 FHS wrapper cannot dlopen nixpkgs ORT, use the MS
ORT build+runtime script (builds, patches, headless smoke):

```bash
bash tools/godot_46_ms_ort.sh
# expect: GODOT_46_MS_ORT_SMOKE_OK
```

Run that from a **plain shell** (not inside `nix develop`). It fetches MS ORT
1.20.1, builds against those headers, bundles the `.so`, and on Nix patches
`libstdc++` beside the addon.

### Portable zip (no local ORT install)

```bash
bash tools/package_linux_portable.sh
# → /tmp/godot-onnx-loader-linux-x64-portable.zip
```

CI also uploads this artifact from `package-linux-portable`.

## Dev layout (vizemes-align sibling)

```text
~/work/godot-onnx-loader/          # this repo → builds addons/onnx_loader/
~/work/vizemes-align/
  godot-demo/
    addons/onnx_loader -> ../../godot-onnx-loader/addons/onnx_loader
```

## Fixtures

`fixtures/ci-smoke/` — tiny viseme MLP ONNX + CSV probes (same numbers as
[vizemes-align](https://github.com/DynamicDevices/vizemes-align) `export/ci-smoke/`).
Softmax stays in GDScript/C smoke; the loader stays generic.

## Known issues / ways forward

### Downloaded `libonnxruntime.so` vs Godot / Nix

The GDExtension **dlopens** `libonnxruntime.so.1` at runtime (it does not link
ORT into the addon `.so`). That keeps a single ORT instance process-wide, but
means the `.so` must load under whatever dynamic linker environment Godot uses.

| Situation | What happens | What to do |
|-----------|--------------|------------|
| Ubuntu / generic Linux + MS ORT 1.20.1 | Works with system `libstdc++` | Quick start above |
| `nix develop` + Godot 4.5 (`godot_4`) | Store ORT matches the shell | `bash tools/godot_csv_smoke.sh` |
| Godot 4.6 FHS on Nix + nixpkgs ORT | dlopen fails (ABI / libstdc++) | `bash tools/godot_46_ms_ort.sh` |
| Build headers ≠ runtime ORT | `GetApi` / load failures | Same ORT for build and runtime |

`ONNX_LOADER_SKIP_SESSION_RELEASE` defaults **on** under Godot 4.6 (skips
`ReleaseSession` and `ReleaseEnv` on destroy — leaks until process exit). Set
`=0` only when deliberately testing ORT teardown.

### Ways forward

1. **Ship MS ORT beside the addon** (current default for non-Nix / portable zip).
2. **Use nixpkgs ORT inside `nix develop`** for Godot 4.5 day-to-day work.
3. **Compile ONNX Runtime from source** (submodule / webrtc-native-style static
   link) if you need a fully controlled ABI — not shipped yet; would remove the
   downloaded-`.so` class of problems at the cost of build time and size.

If dlopen fails, the loader prints the real `dlerror()` message once. On Nix,
missing `libstdc++.so.6` next to the bundled ORT usually means the 4.6 script
(or `REQUIRE_NIX_PATCH=1 bash tools/patch_bundled_ort_rpath.sh`) was skipped.

## License

MIT (loader code). ONNX fixtures are smoke-test artefacts from vizemes-align training.
