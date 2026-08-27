#!/usr/bin/env bash
# Headless csv_smoke through Godot — run before asking Julian to rebuild.
# Nix: nix develop sets ONNX_ORT_BIN (store ORT) + godot_4. Ubuntu CI bundles MS ORT.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-${GODOT:-${HOME}/Downloads/Godot_v4.6.1-stable_linux.x86_64}}"
ORT_ROOT="${ORT_ROOT:-/tmp/onnxruntime-linux-x64-1.20.1}"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke.txt}"
ORT_BUNDLE="${ORT_BUNDLE:-1}"

if [[ ! -x "$GODOT" ]]; then
	echo "GODOT_BIN must point at Godot 4.x (nix develop sets godot_4)" >&2
	exit 1
fi
if [[ ! -f "$ORT_ROOT/lib/libonnxruntime.so.1" && -z "${ONNX_ORT_BIN:-}" ]]; then
	echo "ORT_ROOT missing libonnxruntime.so.1 (set ORT_ROOT or nix develop)" >&2
	exit 1
fi
if [[ ! -f "$ROOT/demo/addons/onnx_loader/bin/libonnx_loader.linux.template_debug.x86_64.so" ]]; then
	echo "Build addon first: ORT_ROOT=$ORT_ROOT scons platform=linux target=template_debug" >&2
	exit 1
fi
if [[ "$ORT_BUNDLE" != "0" && ! -f "$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1" ]]; then
	echo "Bundled ORT missing — rebuild: scons platform=linux target=template_debug" >&2
	exit 1
fi

# Nix store ORT: keep LD_LIBRARY_PATH from nix develop (protobuf/abseil deps).
# Bundled MS ORT: prefer dlopen path only — drop stray LD_LIBRARY_PATH on Godot.
if [[ -z "${ONNX_ORT_BIN:-}" ]]; then
	unset LD_LIBRARY_PATH
fi
cd "$ROOT/demo"
"$GODOT" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee "$OUT"
grep -q GODOT_ONNX_CSV_SMOKE_OK "$OUT"
bash "$ROOT/tools/check_glibc_free.sh" "$OUT"
echo "GODOT_CSV_SMOKE_OK"
