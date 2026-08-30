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

# Prefer the libstdc++ the Godot binary actually resolves (same process image),
# else the build-shell g++ runtime. Julian mid 1003/1004 — discourse.nixos.org
# “what package provides libstdc++.so.6”: proprietary .so must share one C++ ABI.
GODOT_STDCXX=""
GODOT_GCC_S=""
if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]] && command -v ldd >/dev/null 2>&1; then
	GODOT_STDCXX="$(ldd "$GODOT_BIN" 2>/dev/null | awk '/libstdc\+\+\.so\.6/ {print $3; exit}')"
	GODOT_GCC_S="$(ldd "$GODOT_BIN" 2>/dev/null | awk '/libgcc_s\.so\.1/ {print $3; exit}')"
	if [[ -n "$GODOT_STDCXX" && -f "$GODOT_STDCXX" ]]; then
		echo "patch_bundled_ort_rpath: matching Godot libstdc++ from $GODOT_BIN -> $GODOT_STDCXX"
		CXX_LIB="$(dirname "$GODOT_STDCXX")"
	fi
	if [[ -n "$GODOT_GCC_S" && -f "$GODOT_GCC_S" ]]; then
		GCC_S_LIB="$(dirname "$GODOT_GCC_S")"
	fi
fi

# Copy gcc runtime next to ORT so $ORIGIN resolves the same libs ORT uses internally
# (avoids Godot/Nix LD_LIBRARY_PATH pulling a mismatched libstdc++ into MS ORT).
if [[ "${REQUIRE_NIX_PATCH:-0}" == "1" ]]; then
	if [[ -n "$GODOT_STDCXX" && -f "$GODOT_STDCXX" ]]; then
		cp -Lf "$GODOT_STDCXX" "$BIN_DIR/libstdc++.so.6"
	elif command -v g++ >/dev/null 2>&1; then
		STDCXX_SO="$(g++ -print-file-name=libstdc++.so.6)"
		if [[ -f "$STDCXX_SO" ]]; then
			cp -Lf "$STDCXX_SO" "$BIN_DIR/"
		fi
	fi
	if [[ -n "$GODOT_GCC_S" && -f "$GODOT_GCC_S" ]]; then
		cp -Lf "$GODOT_GCC_S" "$BIN_DIR/libgcc_s.so.1"
	elif command -v g++ >/dev/null 2>&1; then
		GCC_S_SO="$(g++ -print-file-name=libgcc_s.so.1)"
		if [[ -f "$GCC_S_SO" ]]; then
			cp -Lf "$GCC_S_SO" "$BIN_DIR/"
		fi
	fi
	add_rpath_if_missing '$ORIGIN'
fi

add_rpath_if_missing "$CXX_LIB"
if [[ -n "$GCC_S_LIB" && -d "$GCC_S_LIB" ]]; then
	add_rpath_if_missing "$GCC_S_LIB"
fi

# patchelf can re-introduce oddities — clear again after rpath edits.
python3 "$ROOT/tools/clear_ort_execstack.py" "$ORT_SO"
python3 "$ROOT/tools/clear_ort_execstack.py" --check "$ORT_SO"

echo "ONNX_ORT_RPATH_OK cxx=$CXX_LIB origin=\$ORIGIN ort=$ORT_SO"
