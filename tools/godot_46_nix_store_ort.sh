#!/usr/bin/env bash
# Nix-native path: nixpkgs godot_4_6 + nixpkgs onnxruntime (no MS bundle).
# Julian mid 1067 / A/B matrix: store Godot + store ORT PASS; MS ORT under nixpkgs Godot free()s.
# Run from godot-onnx-loader root (plain shell with nix available).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NIXPKGS="${NIXPKGS:-github:nixos/nixpkgs/nixos-26.05}"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke-46-store.txt}"
export SCONS_CACHE="${SCONS_CACHE:-$ROOT/.scons-cache-godot46-store}"
mkdir -p "$SCONS_CACHE"

cd "$ROOT"
git submodule update --init --recursive

# Merge lib+dev like flake.nix ortNix (SConstruct wants one ORT_ROOT).
ORT_LIB=$(nix build --no-link --print-out-paths "${NIXPKGS}#onnxruntime")
ORT_DEV=$(nix build --no-link --print-out-paths "${NIXPKGS}#onnxruntime.dev")
ORT_NIX=$(mktemp -d /tmp/onnxruntime-nix-XXXXXX)
mkdir -p "$ORT_NIX/lib" "$ORT_NIX/include"
ln -s "$ORT_LIB"/lib/libonnxruntime.so* "$ORT_NIX/lib/" 2>/dev/null || \
	cp -a "$ORT_LIB"/lib/libonnxruntime.so* "$ORT_NIX/lib/"
cp -a "$ORT_DEV"/include/. "$ORT_NIX/include/"
test -f "$ORT_NIX/include/onnxruntime_c_api.h"

export ORT_ROOT="$ORT_NIX"
export ONNX_ORT_BIN="$ORT_LIB/lib"
export ORT_BUNDLE=0
unset ORT_MS

# Drop any leftover MS bundle so we don't mix.
rm -f addons/onnx_loader/bin/libonnxruntime.so*
rm -f addons/onnx_loader/bin/libstdc++.so.6 addons/onnx_loader/bin/libgcc_s.so.1
rm -f addons/onnx_loader/bin/.ort-bundled.stamp

nix shell "${NIXPKGS}#scons" "${NIXPKGS}#gcc" --command \
	scons -j"$(nproc)" platform=linux target=template_debug

# Symlink store ORT into bin/ so .gdextension [dependencies] resolve (still nixpkgs ORT,
# not a MS copy). Prefer so.1 then so.
ORT_SO_SRC=""
for c in "$ONNX_ORT_BIN"/libonnxruntime.so.1 "$ONNX_ORT_BIN"/libonnxruntime.so; do
	if [[ -f "$c" ]]; then
		ORT_SO_SRC="$c"
		break
	fi
done
test -n "$ORT_SO_SRC"
ln -sfn "$ORT_SO_SRC" addons/onnx_loader/bin/libonnxruntime.so.1
# Also provide unversioned name if Godot/resolve looks for it.
ln -sfn "$ORT_SO_SRC" addons/onnx_loader/bin/libonnxruntime.so

root_q=$(printf '%q' "$ROOT")
out_q=$(printf '%q' "$OUT")
ort_bin_q=$(printf '%q' "$ONNX_ORT_BIN")

nix shell "${NIXPKGS}#godot_4_6" "${NIXPKGS}#onnxruntime" --command bash -c "
set -euo pipefail
export ONNX_ORT_BIN=$ort_bin_q
export ORT_BUNDLE=0
unset ORT_MS
export ONNX_LOADER_SKIP_SESSION_RELEASE=1
bash $root_q/tools/ensure_demo_extension.sh
G=\$(command -v godot4 || command -v godot || true)
test -n \"\$G\" && test -x \"\$G\"
cd $root_q/demo
\"\$G\" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee $out_q
grep -q GODOT_ONNX_CSV_SMOKE_OK $out_q
bash $root_q/tools/check_glibc_free.sh $out_q
echo GODOT_46_NIX_STORE_ORT_SMOKE_OK
"
