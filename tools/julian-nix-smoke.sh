#!/usr/bin/env bash
# Julian's Nix path for Godot 4.6 + MS ORT (not nix develop Godot 4.5).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "=== git ==="
git pull --ff-only
echo "=== Godot 4.6 + MS ORT (godot_46_ms_ort.sh) ==="
bash tools/godot_46_ms_ort.sh
echo "=== check diagnostics in output above ==="
echo "Expect: GODOT_ONNX_CSV_SMOKE_OK / GODOT_46_MS_ORT_SMOKE_OK"
echo "Expect: NO free() abort"
