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
	# DT_RPATH (not RUNPATH): Godot’s Nix FHS sets LD_LIBRARY_PATH, which
	# overrides DT_RUNPATH and can pull a mismatched libstdc++ into MS ORT.
	patchelf --force-rpath --add-rpath "$dir" "$ORT_SO"
}

# Resolve an ELF behind a Nix wrapper script (godot4 is often not the binary).
resolve_godot_elf() {
	local candidate="$1"
	local magic
	[[ -n "$candidate" && -e "$candidate" ]] || return 1
	magic="$(head -c 4 "$candidate" 2>/dev/null || true)"
	if [[ "$magic" == $'\x7fELF' ]]; then
		printf '%s\n' "$candidate"
		return 0
	fi
	python3 - "$candidate" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
seen = set()
for m in re.finditer(r"/nix/store/[0-9a-z]+-[^\s\"']+", text):
    p = Path(m.group(0))
    if p in seen or not p.is_file():
        continue
    seen.add(p)
    try:
        if p.read_bytes()[:4] == b"\x7fELF":
            print(p)
            raise SystemExit(0)
    except OSError:
        pass
raise SystemExit(1)
PY
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
GODOT_ELF=""
if [[ -n "${GODOT_BIN:-}" && -e "${GODOT_BIN}" ]]; then
	GODOT_ELF="$(resolve_godot_elf "$GODOT_BIN" || true)"
fi
if [[ -n "$GODOT_ELF" ]] && command -v ldd >/dev/null 2>&1; then
	GODOT_STDCXX="$(ldd "$GODOT_ELF" 2>/dev/null | awk '/libstdc\+\+\.so\.6/ {print $3; exit}')"
	GODOT_GCC_S="$(ldd "$GODOT_ELF" 2>/dev/null | awk '/libgcc_s\.so\.1/ {print $3; exit}')"
	if [[ -n "$GODOT_STDCXX" && -f "$GODOT_STDCXX" ]]; then
		echo "patch_bundled_ort_rpath: matching Godot libstdc++ from $GODOT_ELF -> $GODOT_STDCXX"
		CXX_LIB="$(dirname "$GODOT_STDCXX")"
	else
		echo "patch_bundled_ort_rpath: Godot ELF $GODOT_ELF has no resolvable libstdc++ via ldd" >&2
	fi
	if [[ -n "$GODOT_GCC_S" && -f "$GODOT_GCC_S" ]]; then
		GCC_S_LIB="$(dirname "$GODOT_GCC_S")"
	fi
elif [[ -n "${GODOT_BIN:-}" ]]; then
	echo "patch_bundled_ort_rpath: could not resolve ELF for GODOT_BIN=$GODOT_BIN (wrapper?)" >&2
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

# Prove we got DT_RPATH (LD_LIBRARY_PATH-proof), not DT_RUNPATH.
if command -v readelf >/dev/null 2>&1; then
	if readelf -d "$ORT_SO" | grep -q '(RUNPATH)'; then
		echo "patch_bundled_ort_rpath: still DT_RUNPATH — rewriting with --force-rpath" >&2
		cur="$(patchelf --print-rpath "$ORT_SO")"
		patchelf --force-rpath --set-rpath "$cur" "$ORT_SO"
		python3 "$ROOT/tools/clear_ort_execstack.py" "$ORT_SO"
	fi
	if ! readelf -d "$ORT_SO" | grep -q '(RPATH)'; then
		echo "patch_bundled_ort_rpath: expected DT_RPATH after force-rpath" >&2
		readelf -d "$ORT_SO" | grep -E 'RPATH|RUNPATH' || true
		exit 1
	fi
	echo "ONNX_ORT_DT_RPATH_OK $(readelf -d "$ORT_SO" | awk '/RPATH/ {print $NF}')"
fi

echo "ONNX_ORT_RPATH_OK cxx=$CXX_LIB origin=\$ORIGIN ort=$ORT_SO"
