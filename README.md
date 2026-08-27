# godot-onnx-loader

Generic **ONNX Runtime GDExtension** for Godot 4.5+ — mat490-style API, Linux/Nix/scons.

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
nix develop   # nixos-25.11: store ORT + godot_4 (4.5.x; CI-green combo)
scons platform=linux target=template_debug
scons smoke-csv   # host CSV table (no Godot required)
```

On NixOS the flake uses **nixpkgs `onnxruntime`** (store path, same libstdc++ as the
loader). `ORT_BUNDLE=0` — no MS tarball copy; `ONNX_ORT_BIN` points at the store lib.
Run Godot from `nix develop` (`GODOT_BIN=godot_4`) so ORT dependencies resolve.

**Godot 4.6:** store ORT from `nix develop` **cannot** dlopen under the godot 4.6 FHS
wrapper. Use **MS ORT 1.20.1 for both build and runtime** (API versions must match — do
not build in `nix develop` then copy MS 1.20.1; nix headers are ORT 1.22 / API 22):

```bash
bash tools/fetch_ms_ort.sh
export ORT_ROOT=/tmp/onnxruntime-linux-x64-1.20.1 ORT_BUNDLE=1
unset ONNX_ORT_BIN
scons platform=linux target=template_debug
bash tools/godot_46_ms_ort.sh   # headless 4.6 smoke (Nix: patchelf libstdc++ into bundled ORT)
```

Run `godot_46_ms_ort.sh` from a **plain shell** (not wrapped in `nix develop`). The script
opens its own `nix shell` for patchelf + Godot 4.6 with `NIX_CXX_LIB` set. If you build
with `nix develop` first, you still need that script (or manually `REQUIRE_NIX_PATCH=1 bash
tools/patch_bundled_ort_rpath.sh` with `NIX_CXX_LIB` from nix `g++`) before Godot 4.6 —
otherwise bundled ORT dlopen fails with `(null)`.

Or use the **portable zip** CI artifact (addon + MS ORT built together). For daily
work, `nix develop` + `$GODOT_BIN` (~4.5) + `bash tools/godot_csv_smoke.sh` stays green.

On Linux the GDExtension links **libstdc++ statically** (openxr/webrtc pattern) so the
`.so` itself does not depend on the host's `libstdc++.so.6`. You still need a compatible
`libonnxruntime.so` at runtime (bundled MS tarball, nixpkgs store path, or distro package
via `ONNX_ORT_BIN`).

Ubuntu CI still bundles the Microsoft ORT 1.20.1 tarball for non-Nix hosts.

**Portable download (generic Linux):** CI job `package-linux-portable` uploads a zip
with `addons/onnx_loader/` + bundled MS ORT. Build locally:

```bash
bash tools/package_linux_portable.sh
# → /tmp/godot-onnx-loader-linux-x64-portable.zip
```

Our GDExtension static-links libstdc++; MS ORT still uses the host libstdc++.so.6
(same as Godot on normal distros). A fully static ORT would require compiling
onnxruntime from source (webrtc-native pattern) — not shipped by Microsoft.

`scons` copies `libonnxruntime.so.1` into `addons/onnx_loader/bin/` when bundling
(non-Nix). The GDExtension **dlopens** ORT at runtime. After rebuild, check
`get_diagnostics()["ort_library_path"]` — on Nix expect a `/nix/store/...` path.

Godot 4.5+ (optional):

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
