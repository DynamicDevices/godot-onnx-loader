#!/usr/bin/env bash
# Patch bundled MS libonnxruntime.so.1 for Godot/Nix:
#  - clear executable stack (glibc 2.41+ rejects RWE GNU_STACK)
#  - on Nix: rpath + copy libstdc++/libgcc_s beside ORT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_SO="$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1"
# shellcheck source=tools/nix_cxx_lib.sh
source "$ROOT/tools/nix_cxx_lib.sh"

add_rpath_if_missing() {
	local dir="$1"
	local current
	current="$(patchelf --print-rpath "$ORT_SO" 2>/dev/null || true)"
	if echo "$current" | tr ':' '\n' | grep -Fxq "$dir"; then
		return 0
	fi
	patchelf --add-rpath "$dir" "$ORT_SO"
}

if [[ ! -f "$ORT_SO" ]]; then
	echo "patch_bundled_ort_rpath: missing $ORT_SO (run scons first)" >&2
	exit 1
fi

# Always clear execstack — required on glibc 2.41+ (Julian/Nix Godot 4.6 dlopen).
python3 "$ROOT/tools/clear_ort_execstack.py" "$ORT_SO"

CXX_LIB="$(resolve_nix_cxx_lib || true)"
GCC_S_LIB="$(resolve_nix_gcc_s_lib || true)"

if [[ -z "$CXX_LIB" || ! -d "$CXX_LIB" ]]; then
	if [[ "${REQUIRE_NIX_PATCH:-0}" == "1" ]]; then
		echo "patch_bundled_ort_rpath: NIX_CXX_LIB required but not set (g++=$(command -v g++ || echo missing))" >&2
		exit 1
	fi
	echo "patch_bundled_ort_rpath: NIX_CXX_LIB not set — rpath skip (non-Nix host); execstack cleared"
	exit 0
fi
if ! command -v patchelf >/dev/null 2>&1; then
	echo "patch_bundled_ort_rpath: patchelf required on Nix" >&2
	exit 1
fi

BIN_DIR="$(dirname "$ORT_SO")"

# Copy gcc runtime next to ORT so $ORIGIN resolves the same libs ORT uses internally
# (avoids Godot/Nix LD_LIBRARY_PATH pulling a mismatched libstdc++ into MS ORT).
if [[ "${REQUIRE_NIX_PATCH:-0}" == "1" ]] && command -v g++ >/dev/null 2>&1; then
	STDCXX_SO="$(g++ -print-file-name=libstdc++.so.6)"
	GCC_S_SO="$(g++ -print-file-name=libgcc_s.so.1)"
	if [[ -f "$STDCXX_SO" ]]; then
		cp -Lf "$STDCXX_SO" "$BIN_DIR/"
	fi
	if [[ -f "$GCC_S_SO" ]]; then
		cp -Lf "$GCC_S_SO" "$BIN_DIR/"
	fi
	add_rpath_if_missing '$ORIGIN'
fi

add_rpath_if_missing "$CXX_LIB"
if [[ -n "$GCC_S_LIB" && -d "$GCC_S_LIB" ]]; then
	add_rpath_if_missing "$GCC_S_LIB"
fi

# patchelf can re-introduce oddities — clear again after rpath edits.
python3 "$ROOT/tools/clear_ort_execstack.py" "$ORT_SO"

echo "ONNX_ORT_RPATH_OK cxx=$CXX_LIB origin=\$ORIGIN ort=$ORT_SO"
