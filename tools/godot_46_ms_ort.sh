#!/usr/bin/env bash
# Godot 4.6 + MS ORT 1.20.1 (build + runtime must match — not nix store ORT headers).
# On NixOS: patchelf bundled MS ORT so libstdc++.so.6 resolves under Godot 4.6 FHS.
# Run from repo root: bash tools/godot_46_ms_ort.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_MS="${ORT_MS:-/tmp/onnxruntime-linux-x64-1.20.1}"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke-46-ms.txt}"

cd "$ROOT"
ORT_ROOT="$ORT_MS" bash tools/fetch_ms_ort.sh >/dev/null
export ORT_ROOT="$ORT_MS"
export ORT_BUNDLE=1
unset ONNX_ORT_BIN
git submodule update --init --recursive

# .ort-bundled.stamp can be stale if libonnxruntime.so.1 was removed — force rebundle.
rm -f addons/onnx_loader/bin/.ort-bundled.stamp
scons -j"$(nproc)" platform=linux target=template_debug smoke-dlopen-ort

ORT_SO="$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1"
if [[ ! -f "$ORT_SO" ]]; then
	echo "godot_46_ms_ort: missing $ORT_SO after scons (ORT_ROOT=$ORT_ROOT ORT_BUNDLE=$ORT_BUNDLE)" >&2
	exit 1
fi

root_q=$(printf '%q' "$ROOT")
out_q=$(printf '%q' "$OUT")

nix shell github:nixos/nixpkgs/nixos-25.11#patchelf github:nixos/nixpkgs/nixos-25.11#gcc \
	github:nixos/nixpkgs/nixos-26.05#godot_4_6 --command bash -c "
set -euo pipefail
export NIX_CXX_LIB=\$(dirname \"\$(dirname \"\$(readlink -f \"\$(command -v g++)\")\")\")/lib
bash $root_q/tools/patch_bundled_ort_rpath.sh
./$root_q/build/smoke_dlopen_ort $root_q/addons/onnx_loader/bin $root_q/fixtures/ci-smoke/model.onnx
unset ONNX_ORT_BIN
unset LD_LIBRARY_PATH
G=\$(command -v godot4 || command -v godot || true)
test -n \"\$G\" && test -x \"\$G\"
cd $root_q/demo
\"\$G\" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee $out_q
grep -q GODOT_ONNX_CSV_SMOKE_OK $out_q
echo GODOT_46_MS_ORT_SMOKE_OK
"
