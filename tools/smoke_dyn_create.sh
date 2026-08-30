#!/usr/bin/env bash
# Host smoke: load_model must succeed for dynamic [batch,time,F] (TCN-style).
# Proves the rebuilt libonnx_runtime.a / bundled ORT accept dynamic non-batch dims.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ONNX="$ROOT/fixtures/ci-smoke/model_dyn_btf.onnx"
ORTDIR="$ROOT/addons/onnx_loader/bin"
OUT_BIN="$ROOT/build/smoke_dyn_create"
NIXPKGS="${NIXPKGS:-github:nixos/nixpkgs/nixos-26.05}"

test -f "$ONNX"
test -f "$ROOT/build/libonnx_runtime.a" || {
	echo "smoke_dyn_create: missing build/libonnx_runtime.a — run scons template_debug first" >&2
	exit 1
}
test -f "$ORTDIR/libonnxruntime.so.1" -o -f "$ORTDIR/libonnxruntime.so" || {
	echo "smoke_dyn_create: missing bundled ORT in $ORTDIR" >&2
	exit 1
}

mkdir -p "$ROOT/build"
cat > "$ROOT/build/smoke_dyn_create.c" <<'C'
#include "onnx_runtime.h"
#include <stdio.h>
int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: smoke_dyn_create model.onnx\n");
		return 2;
	}
	fprintf(stderr, "ONNX_LOADER_BUILD_STAMP %s\n", ONNX_LOADER_BUILD);
	OnnxRuntime *rt = onnx_runtime_create(argv[1]);
	if (!rt) {
		fprintf(stderr, "ONNX_LOADER_DYN_CREATE_FAIL\n");
		return 1;
	}
	if (onnx_runtime_input_size(rt) != -1 || onnx_runtime_output_size(rt) != -1) {
		fprintf(stderr, "ONNX_LOADER_DYN_CREATE_FAIL expected isize/osize -1 got %d/%d\n",
			onnx_runtime_input_size(rt), onnx_runtime_output_size(rt));
		onnx_runtime_destroy(rt);
		return 1;
	}
	fprintf(stderr, "ONNX_LOADER_DYN_CREATE_OK build=%s in=%s out=%s\n",
		ONNX_LOADER_BUILD, onnx_runtime_input_name(rt), onnx_runtime_output_name(rt));
	onnx_runtime_destroy(rt);
	return 0;
}
C

_gcc() {
	if [[ -d /nix/store ]] && command -v nix >/dev/null 2>&1; then
		nix shell "${NIXPKGS}#gcc" --command gcc "$@"
	else
		gcc "$@"
	fi
}

_gcc -O0 -I "$ROOT/src" "$ROOT/build/smoke_dyn_create.c" "$ROOT/build/libonnx_runtime.a" \
	-L "$ORTDIR" -lonnxruntime -Wl,-rpath,"$ORTDIR" -ldl -lpthread -lm -o "$OUT_BIN"

# Also confirm the GDExtension .so was stamped with the same build id.
# (Avoid `strings | grep -q` under pipefail — early SIGPIPE false-fails.)
SO="$ORTDIR/libonnx_loader.linux.template_debug.x86_64.so"
if [[ -f "$SO" ]]; then
	if ! grep -aFob 'ort-meta-vizemes-20260830a' "$SO" >/dev/null; then
		echo "smoke_dyn_create: $SO missing build stamp ort-meta-vizemes-20260830a (stale .so?)" >&2
		grep -aFo 'ort-meta-vizemes-[0-9a-z]*' "$SO" || true
		exit 1
	fi
	echo "ONNX_LOADER_SO_STAMP_OK ort-meta-vizemes-20260830a"
fi

bash "$ROOT/tools/with_bundled_ort.sh" "$OUT_BIN" "$ONNX"
