#!/usr/bin/env bash
# Run host smokes with bundled ORT first, keeping nix shellHook libs (libstdc++).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="${ROOT}/addons/onnx_loader/bin${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "$@"
