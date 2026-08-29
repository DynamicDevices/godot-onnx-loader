# godot-onnx-loader

[![CI](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml/badge.svg)](https://github.com/DynamicDevices/godot-onnx-loader/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DynamicDevices/godot-onnx-loader)](https://github.com/DynamicDevices/godot-onnx-loader/releases/latest)
[![Godot](https://img.shields.io/badge/Godot-4.6%2B-blue?logo=godotengine&logoColor=white)](https://godotengine.org/)

A small [Godot](https://godotengine.org/) 4.6+ addon that runs **ONNX** machine-learning
models inside a game/project (Microsoft ONNX Runtime 1.20.1).

- **ONNX** ([Open Neural Network Exchange](https://onnx.ai/)) is a common file format
  (`.onnx`) for trained models so different tools can share them.
- **ORT** here means **ONNX Runtime** — Microsoft’s engine that loads those `.onnx`
  files and runs them. This addon talks to the C library
  `libonnxruntime.so` (we say “ORT” as shorthand for that runtime, not for a
  separate product).

We only pass float tensors in and out — no model-specific preprocessing.

Fork/refreshed from [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders).

## API (`OnnxLoader`)

| Method | Description |
|--------|-------------|
| `load_model(onnx_path)` | Load `.onnx`; introspects input/output sizes |
| `predict(PackedFloat32Array)` | Raw float logits/outputs |
| `predict_array(Array)` | mat490-compatible `Array` wrapper |
| `get_input_size()` / `get_output_size()` | Flat element counts (batch=1) |

## Install (Godot project)

**Easiest:** download a zip from the
[latest release](https://github.com/DynamicDevices/godot-onnx-loader/releases/latest),
unzip, and copy `addons/onnx_loader/` into your project. Restart the editor / enable
the GDExtension if prompted.

- **Multi-platform** (Linux + Windows + macOS): `godot-onnx-loader-*-assetlib.zip`
- **Linux only** (smaller): `godot-onnx-loader-*-linux-x86_64.zip`

When listed on the [Godot Asset Library](https://godotengine.org/asset-library/asset),
you can also install from the editor: **AssetLib** → search **OnnxLoader**.

Bundles Microsoft ONNX Runtime 1.20.1. The addon loads ORT **from its own `bin/`**
first (no env vars). NixOS: prefer building from source (`tools/godot_46_ms_ort.sh`)
if the glibc prebuild does not match your Godot FHS wrapper.

## Quick start (build from source)

```bash
git clone --recurse-submodules https://github.com/DynamicDevices/godot-onnx-loader.git
cd godot-onnx-loader
# Optional: nix develop   # pins tools via flake.lock
scons platform=linux target=template_debug
scons smoke-csv                 # host CSV smoke (no Godot)
# Godot headless needs **4.6+** (addon compatibility_minimum). Prefer:
bash tools/godot_46_ms_ort.sh   # build + smoke (NixOS / MS ORT)
# or, with a 4.6 binary already built:
bash tools/godot_csv_smoke.sh   # skips nix Godot 4.5; set GODOT_BIN to 4.6+
```

If `ORT_ROOT` is unset, `scons` downloads **Microsoft ONNX Runtime 1.20.1**
(Linux x64 CPU build) into `/tmp` and copies `libonnxruntime.so.1` next to the
addon:

- Release notes / downloads:
  [ONNX Runtime v1.20.1](https://github.com/microsoft/onnxruntime/releases/tag/v1.20.1)
- Exact archive this repo uses:
  [onnxruntime-linux-x64-1.20.1.tgz](https://github.com/microsoft/onnxruntime/releases/download/v1.20.1/onnxruntime-linux-x64-1.20.1.tgz)
- What ONNX Runtime is:
  [ONNX Runtime overview](https://onnxruntime.ai/)

Open `demo/` in Godot 4.6+ → run `csv_smoke.tscn` → expect `GODOT_ONNX_CSV_SMOKE_OK`.
(`demo/.godot/` is local editor cache; do not commit it.)

### Godot 4.6 on NixOS (should just work after build)

Do **not** use the `nix develop` store copy of ONNX Runtime for Godot 4.6.
Build once with the Microsoft runtime bundled (SCons patches it for Nix):

```bash
# plain shell (outside nix develop)
bash tools/fetch_ms_ort.sh
export ORT_ROOT=/tmp/onnxruntime-linux-x64-1.20.1 ORT_BUNDLE=1
unset ONNX_ORT_BIN
scons platform=linux target=template_debug
```

Then open the demo with Godot 4.6 normally — no special wrapper:

```bash
nix shell github:nixos/nixpkgs/nixos-26.05#godot_4_6 -c godot4 --path demo
# or: Godot project manager → Import → demo/
```

One-shot build + headless check (CI uses this): `bash tools/godot_46_ms_ort.sh`.

### Asset Library / project zip

```bash
bash tools/package_assetlib.sh
# → /tmp/godot-onnx-loader-<ver>-linux-x86_64.zip
# unzip and copy addons/onnx_loader into your Godot project
```

Tagged releases upload that zip automatically (see `.github/workflows/release.yml`).
Legacy debug-only: `bash tools/package_linux_portable.sh`.

## Layout

```text
addons/onnx_loader/          # ship this folder into a Godot project
  onnx_loader.gdextension
  README.md
  LICENSE
  bin/                       # loader .so (debug+release) + libonnxruntime.so.1
demo/                        # tiny test project
godot-cpp/                   # C++ bindings (git submodule)
```

## Known issues (especially Nix)

### What goes wrong on NixOS?

On a normal Linux distro (Ubuntu, etc.), Godot and `libonnxruntime.so` both use
the system C++ library (`libstdc++`). On **NixOS** there is no single system
library tree — each package brings its own. Godot from nixpkgs is also wrapped
in an [FHS-style environment](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments)
so it looks like a normal Linux app.

That mismatch shows up as:

1. **Godot 4.5 + `nix develop`** — works, because the flake gives you matching
   Godot + ONNX Runtime from the same nixpkgs pin (`flake.lock`).
2. **Godot 4.6 from nixpkgs + the nixpkgs ONNX Runtime** — often **cannot load**
   the runtime library inside Godot’s wrapper (missing/wrong `libstdc++`, or
   worse crashes when shutting down). That is why we ship the **Microsoft**
   prebuilt `.so` for the 4.6 path and adjust it with `patchelf` on Nix.
3. **“Executable stack” dlopen errors** on newer glibc (2.41+) — some prebuilt
   libraries still ask for an executable stack; the OS refuses. We clear that
   flag when bundling (`tools/clear_ort_execstack.py`).
   Background: [glibc 2.41 release notes (security hardening)](https://sourceware.org/pipermail/libc-announce/2025/000044.html).

Useful Nix docs:

- [Nixpkgs manual — FHS environments](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments)
- [NixOS FAQ — libraries / proprietary binaries](https://nixos.wiki/wiki/Packaging/Binaries) (why random `.so` files break)

### Why does everything recompile when I switch shells?

`nix develop` (flake → nixos-25.11 tools) and `godot_46_ms_ort.sh` (nixpkgs
**26.05** + MS ORT headers) are **different compilers and header sets**.
SCons correctly rebuilds `godot-cpp` when the toolchain changes.

Mitigation: each path uses its own build cache directory so you are not
constantly wiping the other:

- `nix develop` → default / `SCONS_CACHE` you export
- `godot_46_ms_ort.sh` → `.scons-cache-godot46-ms` in the repo (override with
  `SCONS_CACHE=...`)

First run on each path is still a full build; later runs on the **same** path
should be incremental.

### Short “what should I run?” table

| Your machine | Goal | Command |
|--------------|------|---------|
| Ubuntu / Fedora / similar | Day-to-day | Quick start above |
| NixOS | Godot **4.5** | Host `scons smoke-csv` only — editor smoke needs 4.6 (`godot_csv_smoke.sh` refuses 4.5) |
| NixOS | Godot **4.6** | Plain shell: `bash tools/godot_46_ms_ort.sh` |
| Any | Missing `libonnxruntime.so.1` | Re-run `scons` with bundling, or set `ONNX_ORT_BIN` to the folder that contains the `.so` |

### Shutdown / teardown note

On Godot 4.6 we default to **not** fully releasing ONNX Runtime sessions on
exit (avoids a known heap crash). That leaks until process exit; fine for
editor/smoke. Set `ONNX_LOADER_SKIP_SESSION_RELEASE=0` only if you are
deliberately testing teardown.

Longer term: compiling ONNX Runtime ourselves (submodule) would avoid several
downloaded-`.so` problems, at the cost of build time.

## License

MIT — see [LICENSE](LICENSE). ONNX fixtures are smoke-test artefacts from
vizemes-align training. Bundled `libonnxruntime` is Microsoft ONNX Runtime
(separate license; see [onnxruntime.ai](https://onnxruntime.ai/)).

## Asset Library submit (maintainers)

Checklist for [godotengine.org/asset-library/asset/submit](https://godotengine.org/asset-library/asset/submit):

1. Push tag `vX.Y.Z` on `main` → workflow `release.yml` builds and attaches
   `godot-onnx-loader-vX.Y.Z-linux-x86_64.zip` to the GitHub Release.
2. Copy the **direct** release asset URL (not an Actions artifact URL — those expire), e.g.
   `https://github.com/DynamicDevices/godot-onnx-loader/releases/download/v0.2.0/godot-onnx-loader-v0.2.0-linux-x86_64.zip`
3. Submit form fields:
   - **Title:** OnnxLoader (or godot-onnx-loader)
   - **Category:** Scripts / Tools (Misc is fine if Scripts is a poor fit)
   - **Godot version / Minimum:** **4.6**
   - **Download provider:** **Custom**
   - **Download URL:** the zip URL from step 2
   - **Description:** GDExtension for running ONNX models (Microsoft ONNX Runtime 1.20.1 bundled). **Linux x86_64 only** in this package (debug + release). Windows/macOS builds exist in CI but are not in the AssetLib zip yet. NixOS: prefer building from the git repo.
   - **License:** MIT
4. After listing, update the Install section above with the AssetLib page link.
5. Review can take days; do not point Custom URL at a CI artifact.
