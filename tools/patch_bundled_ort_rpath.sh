#!/usr/bin/env bash
# MS libonnxruntime.so.1 needs libstdc++.so.6 at dlopen — patch bundled copy on Nix.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_SO="$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1"
CXX_LIB="${NIX_CXX_LIB:-}"

if [[ ! -f "$ORT_SO" ]]; then
	echo "patch_bundled_ort_rpath: missing $ORT_SO (run scons first)" >&2
	exit 1
fi
if [[ -z "$CXX_LIB" || ! -d "$CXX_LIB" ]]; then
	echo "patch_bundled_ort_rpath: NIX_CXX_LIB not set — skip (non-Nix host)" >&2
	exit 0
fi
if ! command -v patchelf >/dev/null 2>&1; then
	echo "patch_bundled_ort_rpath: patchelf required on Nix" >&2
	exit 1
fi

# Idempotent: add nix libstdc++ if not already on RUNPATH/RPATH.
if patchelf --print-rpath "$ORT_SO" 2>/dev/null | tr ':' '\n' | grep -Fxq "$CXX_LIB"; then
	echo "ONNX_ORT_RPATH_OK already has $CXX_LIB"
	exit 0
fi
patchelf --add-rpath "$CXX_LIB" "$ORT_SO"
echo "ONNX_ORT_RPATH_OK added $CXX_LIB to bundled libonnxruntime.so.1"
