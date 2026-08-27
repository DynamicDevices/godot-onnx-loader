#!/usr/bin/env bash
# Headless csv_smoke with Godot 4.6 + MS ORT (not nix store — store dlopen fails under godot_4_6 FHS).
# Run: nix develop --command bash tools/godot_46_csv_smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke-46.txt}"
BIN="$ROOT/demo/addons/onnx_loader/bin"
ORT_MS="${ORT_MS:-/tmp/onnxruntime-linux-x64-1.20.1}"

if [[ ! -f "$BIN/libonnx_loader.linux.template_debug.x86_64.so" ]]; then
	echo "Build addon first: scons platform=linux target=template_debug" >&2
	exit 1
fi

ORT_ROOT="$ORT_MS" bash "$ROOT/tools/fetch_ms_ort.sh" >/dev/null
cp -f "$ORT_MS/lib/libonnxruntime.so" "$ORT_MS/lib/libonnxruntime.so.1" "$BIN/"
test -f "$ORT_MS/lib/libonnxruntime.so.1"

ort_ms_q=$(printf '%q' "$ORT_MS/lib")
root_q=$(printf '%q' "$ROOT")
out_q=$(printf '%q' "$OUT")

nix shell github:nixos/nixpkgs/nixos-26.05#godot_4_6 --command bash -c "
set -euo pipefail
export ONNX_ORT_BIN=$ort_ms_q
export LD_LIBRARY_PATH=$ort_ms_q
export ORT_BUNDLE=0
G=\$(command -v godot4 || command -v godot || true)
if [[ -z \"\$G\" || ! -x \"\$G\" ]]; then
	echo 'godot_4_6 binary not found in nix shell' >&2
	exit 1
fi
cd $root_q/demo
\"\$G\" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee $out_q
grep -q GODOT_ONNX_CSV_SMOKE_OK $out_q
bash $root_q/tools/check_glibc_free.sh $out_q
echo GODOT_46_CSV_SMOKE_OK
"
