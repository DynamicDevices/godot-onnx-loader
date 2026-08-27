#!/usr/bin/env bash
# Build a generic Linux zip: GDExtension (static libstdc++) + bundled MS ORT.
# For Nix use nix develop + store ORT instead — see README.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${ORT_MS_VER:-1.20.1}"
OUT_DIR="${OUT_DIR:-/tmp/godot-onnx-loader-portable}"
ZIP="${ZIP:-/tmp/godot-onnx-loader-linux-x64-portable.zip}"
TARGET="${TARGET:-template_debug}"

cd "$ROOT"
export ORT_ROOT="${ORT_ROOT:-/tmp/onnxruntime-linux-x64-${VER}}"
export ORT_BUNDLE=1
unset ONNX_ORT_BIN

bash tools/fetch_ms_ort.sh
if [[ "${SKIP_SCONS:-0}" != "1" ]]; then
  git submodule update --init --recursive
  scons platform=linux target="$TARGET"
fi

SO="addons/onnx_loader/bin/libonnx_loader.linux.${TARGET}.x86_64.so"
ORT_SO="addons/onnx_loader/bin/libonnxruntime.so.1"
test -f "$SO"
test -f "$ORT_SO"
! ldd "$SO" | grep -q libonnxruntime
! ldd "$SO" | grep -q 'libstdc++'

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/addons/onnx_loader/bin"
cp -a addons/onnx_loader/bin/libonnx_loader.linux."${TARGET}".x86_64.so "$OUT_DIR/addons/onnx_loader/bin/"
cp -a addons/onnx_loader/bin/libonnxruntime.so.1 "$OUT_DIR/addons/onnx_loader/bin/"
cp -a addons/onnx_loader/bin/libonnxruntime.so "$OUT_DIR/addons/onnx_loader/bin/" 2>/dev/null || true
cp -a addons/onnx_loader/onnx_loader.gdextension "$OUT_DIR/addons/onnx_loader/"
cp -a addons/onnx_loader/onnx_loader.gd "$OUT_DIR/addons/onnx_loader/" 2>/dev/null || true

cat >"$OUT_DIR/PORTABLE.txt" <<EOF
godot-onnx-loader portable Linux x64 (${TARGET})

Contents:
  addons/onnx_loader/bin/libonnx_loader.so — GDExtension (static libstdc++)
  addons/onnx_loader/bin/libonnxruntime.so.1 — MS ORT ${VER} (dynamic libstdc++)

Use with official Godot 4.x editor (template_${TARGET#template_} build).
Copy addons/onnx_loader into your project (or symlink).

ORT is dlopened at runtime from addons/onnx_loader/bin/.
On typical Ubuntu/Fedora, MS ORT shares the system libstdc++.so.6 with Godot.

NixOS: use nix develop in godot-onnx-loader instead of this zip.
EOF

rm -f "$ZIP"
(cd "$OUT_DIR" && zip -rq "$ZIP" .)
echo "PORTABLE_PACKAGE_OK zip=$ZIP"
ls -lh "$ZIP"
