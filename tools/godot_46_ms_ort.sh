#!/usr/bin/env bash
# Godot 4.6 + MS ORT 1.20.1 (build + runtime must match — not nix store ORT headers).
# On NixOS: patchelf bundled MS ORT so libstdc++.so.6 resolves under Godot 4.6 FHS.
# On Ubuntu/generic: skip nix/patchelf; use GODOT_BIN (or Downloads 4.6.1).
# Run from repo root: bash tools/godot_46_ms_ort.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_MS="${ORT_MS:-/tmp/onnxruntime-linux-x64-1.20.1}"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke-46-ms.txt}"
# Godot 4.6 + gcc runtime must come from the same nixpkgs rev (Nix path only).
NIXPKGS="${NIXPKGS:-github:nixos/nixpkgs/nixos-26.05}"

cd "$ROOT"
ORT_ROOT="$ORT_MS" bash tools/fetch_ms_ort.sh >/dev/null
export ORT_ROOT="$ORT_MS"
export ORT_BUNDLE=1
unset ONNX_ORT_BIN
git submodule update --init --recursive

# Stale bundled gcc copies / stamp confuse rebuilds.
rm -f addons/onnx_loader/bin/.ort-bundled.stamp
rm -f addons/onnx_loader/bin/libstdc++.so.6 addons/onnx_loader/bin/libgcc_s.so.1

_scons() {
	if command -v scons >/dev/null 2>&1; then
		scons "$@"
	else
		nix shell "${NIXPKGS}#scons" "${NIXPKGS}#gcc" --command scons "$@"
	fi
}

_scons -j"$(nproc)" platform=linux target=template_debug smoke-dlopen-ort

ORT_SO="$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1"
if [[ ! -f "$ORT_SO" ]]; then
	echo "godot_46_ms_ort: missing $ORT_SO after scons (ORT_ROOT=$ORT_ROOT ORT_BUNDLE=$ORT_BUNDLE)" >&2
	exit 1
fi

_run_godot_smoke() {
	local godot="$1"
	unset ONNX_ORT_BIN
	export ONNX_LOADER_SKIP_SESSION_RELEASE=1
	bash "$ROOT/tools/ensure_demo_extension.sh"
	cd "$ROOT/demo"
	"$godot" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee "$OUT"
	grep -q GODOT_ONNX_CSV_SMOKE_OK "$OUT"
	bash "$ROOT/tools/check_glibc_free.sh" "$OUT"
	echo GODOT_46_MS_ORT_SMOKE_OK
}

# Non-Nix hosts: use a local Godot 4.6 binary (no patchelf needed for MS ORT).
_host_godot="${GODOT_BIN:-${GODOT:-}}"
if [[ -z "$_host_godot" && -x "${HOME}/Downloads/Godot_v4.6.1-stable_linux.x86_64" ]]; then
	_host_godot="${HOME}/Downloads/Godot_v4.6.1-stable_linux.x86_64"
fi

if ! command -v nix >/dev/null 2>&1; then
	if [[ -z "$_host_godot" || ! -x "$_host_godot" ]]; then
		echo "godot_46_ms_ort: no nix and no Godot 4.6 binary (set GODOT_BIN)" >&2
		exit 1
	fi
	echo "godot_46_ms_ort: non-Nix path using GODOT_BIN=$_host_godot"
	_run_godot_smoke "$_host_godot"
	exit 0
fi

root_q=$(printf '%q' "$ROOT")
out_q=$(printf '%q' "$OUT")

nix shell "${NIXPKGS}#patchelf" "${NIXPKGS}#gcc" "${NIXPKGS}#godot_4_6" --command bash -c "
set -euo pipefail
source $root_q/tools/nix_cxx_lib.sh
export NIX_CXX_LIB=\$(resolve_nix_cxx_lib || true)
if [[ -z \"\$NIX_CXX_LIB\" || ! -d \"\$NIX_CXX_LIB\" ]]; then
	echo \"godot_46_ms_ort: NIX_CXX_LIB unresolved (g++=\$(command -v g++ || echo missing))\" >&2
	exit 1
fi
REQUIRE_NIX_PATCH=1 bash $root_q/tools/patch_bundled_ort_rpath.sh
if ! patchelf --print-rpath $root_q/addons/onnx_loader/bin/libonnxruntime.so.1 | tr ':' '\\n' | grep -Fxq \"\$NIX_CXX_LIB\"; then
	echo \"godot_46_ms_ort: bundled ORT missing libstdc++ rpath after patch\" >&2
	exit 1
fi
if ! patchelf --print-rpath $root_q/addons/onnx_loader/bin/libonnxruntime.so.1 | tr ':' '\\n' | grep -Fxq '\$ORIGIN'; then
	echo \"godot_46_ms_ort: bundled ORT missing \\\$ORIGIN rpath after patch\" >&2
	exit 1
fi
test -f $root_q/addons/onnx_loader/bin/libstdc++.so.6

# Do not unset LD_LIBRARY_PATH — Godot 4.6 nix wrapper sets its own FHS env.
unset ONNX_ORT_BIN
export ONNX_LOADER_SKIP_SESSION_RELEASE=1
bash $root_q/tools/ensure_demo_extension.sh
G=\$(command -v godot4 || command -v godot || true)
test -n \"\$G\" && test -x \"\$G\"
cd $root_q/demo
\"\$G\" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee $out_q
grep -q GODOT_ONNX_CSV_SMOKE_OK $out_q
bash $root_q/tools/check_glibc_free.sh $out_q
echo GODOT_46_MS_ORT_SMOKE_OK
"
