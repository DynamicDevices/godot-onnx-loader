#!/usr/bin/env bash
# Build an Asset Library / Godot-project zip:
#   addons/onnx_loader/  (debug+release .so + MS ORT + LICENSE + README)
# Output: /tmp/godot-onnx-loader-<ver>-linux-x86_64.zip (override with ZIP=)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${ORT_MS_VER:-1.20.1}"
PKG_VER="${PKG_VER:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
OUT_DIR="${OUT_DIR:-/tmp/godot-onnx-loader-assetlib}"
ZIP="${ZIP:-/tmp/godot-onnx-loader-${PKG_VER}-linux-x86_64.zip}"

cd "$ROOT"
export ORT_ROOT="${ORT_ROOT:-/tmp/onnxruntime-linux-x64-${VER}}"
export ORT_BUNDLE=1
unset ONNX_ORT_BIN

bash tools/fetch_ms_ort.sh
if [[ "${SKIP_SCONS:-0}" != "1" ]]; then
	git submodule update --init --recursive
	scons -j"$(nproc)" platform=linux target=template_debug
	scons -j"$(nproc)" platform=linux target=template_release
fi

DBG="addons/onnx_loader/bin/libonnx_loader.linux.template_debug.x86_64.so"
REL="addons/onnx_loader/bin/libonnx_loader.linux.template_release.x86_64.so"
ORT_SO="addons/onnx_loader/bin/libonnxruntime.so.1"
test -f "$DBG"
test -f "$REL"
test -f "$ORT_SO"
! ldd "$DBG" | grep -q libonnxruntime
! ldd "$DBG" | grep -q 'libstdc++'
python3 tools/clear_ort_execstack.py --check "$ORT_SO"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/addons/onnx_loader/bin"
cp -a "$DBG" "$REL" "$ORT_SO" "$OUT_DIR/addons/onnx_loader/bin/"
# Soft link name some loaders expect
if [[ -e addons/onnx_loader/bin/libonnxruntime.so ]]; then
	cp -a addons/onnx_loader/bin/libonnxruntime.so "$OUT_DIR/addons/onnx_loader/bin/"
fi
cp -a addons/onnx_loader/onnx_loader.gdextension "$OUT_DIR/addons/onnx_loader/"
[[ -f addons/onnx_loader/onnx_loader.gdextension.uid ]] && \
	cp -a addons/onnx_loader/onnx_loader.gdextension.uid "$OUT_DIR/addons/onnx_loader/"
cp -a addons/onnx_loader/README.md "$OUT_DIR/addons/onnx_loader/"
cp -a LICENSE "$OUT_DIR/addons/onnx_loader/LICENSE"

rm -f "$ZIP"
(cd "$OUT_DIR" && zip -rq "$ZIP" addons)
echo "ASSETLIB_PACKAGE_OK zip=$ZIP"
ls -lh "$ZIP"
unzip -l "$ZIP" | head -30
