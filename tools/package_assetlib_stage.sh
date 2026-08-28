#!/usr/bin/env bash
# Stage whatever is already under addons/onnx_loader/ into AssetLib zips.
# Used by release.yml after linux/windows/macos build artifacts are merged.
#
# Outputs:
#   ZIP       — multi-platform (default …-assetlib.zip)
#   ZIP_LINUX — Linux-only sibling (default …-linux-x86_64.zip) when MAKE_LINUX_ZIP=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_VER="${PKG_VER:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
OUT_DIR="${OUT_DIR:-/tmp/godot-onnx-loader-assetlib}"
ZIP="${ZIP:-/tmp/godot-onnx-loader-${PKG_VER}-assetlib.zip}"
ZIP_LINUX="${ZIP_LINUX:-/tmp/godot-onnx-loader-${PKG_VER}-linux-x86_64.zip}"
# 1 = require Linux+Windows+macOS (release). 0 = Linux-only OK (local).
REQUIRE_MULTI="${REQUIRE_MULTI:-1}"
MAKE_LINUX_ZIP="${MAKE_LINUX_ZIP:-1}"

cd "$ROOT"
test -f addons/onnx_loader/onnx_loader.gdextension
test -f LICENSE

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/addons/onnx_loader"
cp -a addons/onnx_loader/onnx_loader.gdextension "$OUT_DIR/addons/onnx_loader/"
[[ -f addons/onnx_loader/onnx_loader.gdextension.uid ]] && \
	cp -a addons/onnx_loader/onnx_loader.gdextension.uid "$OUT_DIR/addons/onnx_loader/"
cp -a addons/onnx_loader/README.md "$OUT_DIR/addons/onnx_loader/"
cp -a LICENSE "$OUT_DIR/addons/onnx_loader/LICENSE"

if [[ -d addons/onnx_loader/bin ]]; then
	mkdir -p "$OUT_DIR/addons/onnx_loader/bin"
	cp -a addons/onnx_loader/bin/. "$OUT_DIR/addons/onnx_loader/bin/"
fi

BIN="$OUT_DIR/addons/onnx_loader/bin"
test -f "$BIN/libonnx_loader.linux.template_debug.x86_64.so"
test -f "$BIN/libonnx_loader.linux.template_release.x86_64.so"
test -f "$BIN/libonnxruntime.so.1"

if [[ "$REQUIRE_MULTI" == "1" ]]; then
	test -f "$BIN/libonnx_loader.windows.template_debug.x86_64.dll"
	test -f "$BIN/libonnx_loader.windows.template_release.x86_64.dll"
	test -f "$BIN/onnxruntime.dll"
	test -d "$BIN/libonnx_loader.macos.template_debug.framework"
	test -d "$BIN/libonnx_loader.macos.template_release.framework"
	test -f "$BIN/libonnxruntime.dylib"
fi

rm -f "$ZIP"
(cd "$OUT_DIR" && zip -rq "$ZIP" addons)
test -f "$ZIP"
echo "ASSETLIB_PACKAGE_OK zip=$ZIP require_multi=$REQUIRE_MULTI"
ls -lh "$ZIP"
unzip -l "$ZIP" | head -60 || true

if [[ "$MAKE_LINUX_ZIP" == "1" ]]; then
	LINUX_OUT="${OUT_DIR}-linux-only"
	rm -rf "$LINUX_OUT"
	mkdir -p "$LINUX_OUT/addons/onnx_loader/bin"
	cp -a "$OUT_DIR/addons/onnx_loader/onnx_loader.gdextension" \
		"$OUT_DIR/addons/onnx_loader/README.md" \
		"$OUT_DIR/addons/onnx_loader/LICENSE" \
		"$LINUX_OUT/addons/onnx_loader/"
	cp -a \
		"$BIN/libonnx_loader.linux.template_debug.x86_64.so" \
		"$BIN/libonnx_loader.linux.template_release.x86_64.so" \
		"$BIN/libonnxruntime.so.1" \
		"$LINUX_OUT/addons/onnx_loader/bin/"
	if [[ -e "$BIN/libonnxruntime.so" ]]; then
		cp -a "$BIN/libonnxruntime.so" "$LINUX_OUT/addons/onnx_loader/bin/"
	fi
	rm -f "$ZIP_LINUX"
	(cd "$LINUX_OUT" && zip -rq "$ZIP_LINUX" addons)
	test -f "$ZIP_LINUX"
	echo "ASSETLIB_LINUX_OK zip=$ZIP_LINUX"
	ls -lh "$ZIP_LINUX"
fi
