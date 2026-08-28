#!/usr/bin/env bash
# Run host smokes with a resolvable ORT path for onnx_runtime.c (dlopen).
# Prefer ONNX_ORT_BIN; else the addon-bundled lib (Godot [dependencies] layout).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_BIN="$ROOT/addons/onnx_loader/bin"
BUNDLE_SO="$BUNDLE_BIN/libonnxruntime.so.1"

if [[ -n "${ONNX_ORT_BIN:-}" ]]; then
	:
elif [[ -f "$BUNDLE_SO" ]]; then
	export ONNX_ORT_BIN="$BUNDLE_BIN"
else
	echo "with_bundled_ort: no ONNX_ORT_BIN and missing $BUNDLE_SO" >&2
	echo "  nix develop   # sets ONNX_ORT_BIN to store ORT" >&2
	echo "  or: scons … with ORT_BUNDLE=1 (copies MS ORT into addons/…/bin)" >&2
	exit 1
fi

if [[ -d "$ONNX_ORT_BIN" ]]; then
	export LD_LIBRARY_PATH="${ONNX_ORT_BIN}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
elif [[ -f "$ONNX_ORT_BIN" ]]; then
	export LD_LIBRARY_PATH="$(dirname "$ONNX_ORT_BIN")${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
exec "$@"
