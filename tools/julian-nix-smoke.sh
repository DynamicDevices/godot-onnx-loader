#!/usr/bin/env bash
# Julian's exact smoke path — same as Nix CI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "=== git ==="
git pull --ff-only
echo "=== clean bundled ORT (fix Permission denied) ==="
rm -f addons/onnx_loader/bin/libonnxruntime.so*
echo "=== nix develop + build ==="
nix develop --command bash -c '
  set -euo pipefail
  scons platform=linux target=template_debug
  bash tools/godot_csv_smoke.sh
'
echo "=== check diagnostics in output above ==="
echo "Expect: loader_build ort-deepbind-20260826g (or later)"
echo "Expect: ort_library_path ending in addons/onnx_loader/bin/libonnxruntime.so.1"
echo "Expect: GODOT_ONNX_CSV_SMOKE_OK and NO free(): invalid size"
