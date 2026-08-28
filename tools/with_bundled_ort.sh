#!/usr/bin/env bash
# Run host smokes with a resolvable ORT path for onnx_runtime.c (dlopen).
# Prefer ONNX_ORT_BIN; else the addon-bundled lib (Godot [dependencies] layout).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_BIN="$ROOT/addons/onnx_loader/bin"

pick_bundle() {
	local f
	for f in libonnxruntime.so.1 libonnxruntime.dylib libonnxruntime.1.20.1.dylib onnxruntime.dll; do
		if [[ -f "$BUNDLE_BIN/$f" ]]; then
			echo "$BUNDLE_BIN"
			return 0
		fi
	done
	return 1
}

if [[ -n "${ONNX_ORT_BIN:-}" ]]; then
	:
elif BUNDLE="$(pick_bundle)"; then
	export ONNX_ORT_BIN="$BUNDLE"
else
	echo "with_bundled_ort: no ONNX_ORT_BIN and missing bundled ORT in $BUNDLE_BIN" >&2
	echo "  nix develop   # sets ONNX_ORT_BIN to store ORT" >&2
	echo "  or: scons … with ORT_BUNDLE=1 (copies MS ORT into addons/…/bin)" >&2
	exit 1
fi

if [[ -d "$ONNX_ORT_BIN" ]]; then
	export LD_LIBRARY_PATH="${ONNX_ORT_BIN}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
	export DYLD_LIBRARY_PATH="${ONNX_ORT_BIN}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
elif [[ -f "$ONNX_ORT_BIN" ]]; then
	d="$(dirname "$ONNX_ORT_BIN")"
	export LD_LIBRARY_PATH="${d}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
	export DYLD_LIBRARY_PATH="${d}${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
fi
exec "$@"
