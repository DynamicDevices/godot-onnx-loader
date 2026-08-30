#!/usr/bin/env bash
# Julian's Nix-native path for Godot 4.6 + nixpkgs ORT.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "=== git ==="
git pull --ff-only
echo "=== Godot 4.6 + nixpkgs ORT (godot_46_nix_store_ort.sh) ==="
bash tools/godot_46_nix_store_ort.sh
echo "=== check diagnostics in output above ==="
echo "Expect: GODOT_ONNX_CSV_SMOKE_OK / GODOT_46_NIX_STORE_ORT_SMOKE_OK"
echo "Expect: NO free() abort"
