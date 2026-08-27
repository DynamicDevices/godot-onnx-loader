#!/usr/bin/env bash
# Julian's exact smoke path — same as Nix CI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "=== git ==="
git pull --ff-only
echo "=== clean bundled ORT (fix Permission denied) ==="
rm -f addons/onnx_loader/bin/libonnxruntime.so*
echo "=== nix develop + build + smoke ==="
nix develop --command bash -c '
  set -euo pipefail
  scons platform=linux target=template_debug
  scons platform=linux target=template_debug smoke-dlopen-ort
  bash tools/godot_csv_smoke.sh
'
echo "=== check diagnostics in output above ==="
echo "Expect: loader_build ort-dlopen-godot-official-*"
echo "Expect: GODOT_BIN official Godot 4.5.1 (NOT nixpkgs godot_4)"
echo "Expect: GODOT_ONNX_CSV_SMOKE_OK and NO free() abort"
