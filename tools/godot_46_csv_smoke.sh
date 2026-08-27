#!/usr/bin/env bash
# Headless csv_smoke with Godot 4.6 (nixpkgs) + store ORT from nix develop.
# Run: nix develop --command bash tools/godot_46_csv_smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke-46.txt}"

if [[ -z "${ONNX_ORT_BIN:-}" ]]; then
	echo "Must run inside nix develop (ONNX_ORT_BIN + LD_LIBRARY_PATH)" >&2
	exit 1
fi
if [[ ! -f "$ROOT/demo/addons/onnx_loader/bin/libonnx_loader.linux.template_debug.x86_64.so" ]]; then
	echo "Build addon first: scons platform=linux target=template_debug" >&2
	exit 1
fi

ort_q=$(printf '%q' "$ONNX_ORT_BIN")
ld_q=$(printf '%q' "${LD_LIBRARY_PATH:-}")
root_q=$(printf '%q' "$ROOT")
out_q=$(printf '%q' "$OUT")

nix shell github:nixos/nixpkgs/nixos-26.05#godot_4_6 --command bash -c "
set -euo pipefail
export ONNX_ORT_BIN=$ort_q
export LD_LIBRARY_PATH=$ld_q
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
