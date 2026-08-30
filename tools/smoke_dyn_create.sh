#!/usr/bin/env bash
# Host smoke: load_model must succeed for dynamic [batch,time,F] (TCN-style).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -x "$ROOT/build/smoke_csv" || scons -C "$ROOT" platform=linux target=template_debug build/smoke_csv >/dev/null
# Reuse create via tiny C if present, else compile on the fly
ONNX="$ROOT/fixtures/ci-smoke/model_dyn_btf.onnx"
test -f "$ONNX"
cat > /tmp/smoke_dyn_create.c <<'C'
#include "onnx_runtime.h"
#include <stdio.h>
int main(int argc, char **argv) {
  OnnxRuntime *rt = onnx_runtime_create(argv[1]);
  if (!rt) { fprintf(stderr, "ONNX_LOADER_DYN_CREATE_FAIL\n"); return 1; }
  if (onnx_runtime_input_size(rt) != -1 || onnx_runtime_output_size(rt) != -1) {
    fprintf(stderr, "ONNX_LOADER_DYN_CREATE_FAIL expected isize/osize -1 got %d/%d\n",
            onnx_runtime_input_size(rt), onnx_runtime_output_size(rt));
    onnx_runtime_destroy(rt);
    return 1;
  }
  fprintf(stderr, "ONNX_LOADER_DYN_CREATE_OK build=%s in=%s\n",
          ONNX_LOADER_BUILD, onnx_runtime_input_name(rt));
  onnx_runtime_destroy(rt);
  return 0;
}
C
ORTDIR="$ROOT/addons/onnx_loader/bin"
gcc -O0 -I "$ROOT/src" /tmp/smoke_dyn_create.c "$ROOT/build/libonnx_runtime.a" \
  -L "$ORTDIR" -lonnxruntime -Wl,-rpath,"$ORTDIR" -ldl -lpthread -lm -o /tmp/smoke_dyn_create
bash "$ROOT/tools/with_bundled_ort.sh" /tmp/smoke_dyn_create "$ONNX"
