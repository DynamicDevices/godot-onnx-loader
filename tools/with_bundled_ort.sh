#!/usr/bin/env bash
# Run host smokes with ORT on LD_LIBRARY_PATH (bundled dir or nix store via ONNX_ORT_BIN).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${ONNX_ORT_BIN:-}" ]]; then
	export LD_LIBRARY_PATH="${ONNX_ORT_BIN}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
else
	export LD_LIBRARY_PATH="${ROOT}/addons/onnx_loader/bin${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
exec "$@"
