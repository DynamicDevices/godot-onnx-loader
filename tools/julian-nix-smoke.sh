#!/usr/bin/env bash
# Julian's exact smoke path — same as Nix CI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "=== git ==="
git pull --ff-only
echo "=== nix develop + build + smoke ==="
nix develop --command bash -c '
  set -euo pipefail
  scons platform=linux target=template_debug
  bash tools/godot_csv_smoke.sh
'
echo "=== check diagnostics in output above ==="
echo "Expect: loader_build ort-nix-store-*"
echo "Expect: ort_library_path under /nix/store/ (nixpkgs onnxruntime)"
echo "Expect: GODOT_ONNX_CSV_SMOKE_OK and NO free() abort"
