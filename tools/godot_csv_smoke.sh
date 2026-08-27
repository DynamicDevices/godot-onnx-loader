#!/usr/bin/env bash
# Headless csv_smoke through Godot — run before asking Julian to rebuild.
# Uses GODOT_BIN from nix develop (official Godot 4.5.1 — NOT nixpkgs godot_4).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-${GODOT:-${HOME}/Downloads/Godot_v4.6.1-stable_linux.x86_64}}"
ORT_ROOT="${ORT_ROOT:-/tmp/onnxruntime-linux-x64-1.20.1}"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke.txt}"

if [[ ! -x "$GODOT" ]]; then
	echo "GODOT_BIN must point at Godot 4.x official binary (nix develop sets 4.5.1)" >&2
	exit 1
fi
if [[ ! -f "$ORT_ROOT/lib/libonnxruntime.so.1" ]]; then
	echo "ORT_ROOT missing libonnxruntime.so.1 (set ORT_ROOT or nix develop)" >&2
	exit 1
fi
if [[ ! -f "$ROOT/demo/addons/onnx_loader/bin/libonnx_loader.linux.template_debug.x86_64.so" ]]; then
	echo "Build addon first: ORT_ROOT=$ORT_ROOT scons platform=linux target=template_debug" >&2
	exit 1
fi
if [[ ! -f "$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1" ]]; then
	echo "Bundled ORT missing — rebuild: scons platform=linux target=template_debug" >&2
	exit 1
fi

# MS ORT (dlopen) needs libstdc++.so.6; keep Nix C++ runtime, not nixpkgs ORT.
if [[ -n "${NIX_CXX_LIB:-}" && -d "$NIX_CXX_LIB" ]]; then
	export LD_LIBRARY_PATH="$NIX_CXX_LIB"
else
	unset LD_LIBRARY_PATH
fi
cd "$ROOT/demo"
"$GODOT" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee "$OUT"
grep -q GODOT_ONNX_CSV_SMOKE_OK "$OUT"
bash "$ROOT/tools/check_glibc_free.sh" "$OUT"
echo "GODOT_CSV_SMOKE_OK"
