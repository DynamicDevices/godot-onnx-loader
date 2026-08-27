#!/usr/bin/env bash
# Fetch Microsoft ONNX Runtime linux-x64 CPU prebuild into ORT_ROOT.
set -euo pipefail
VER="${ORT_MS_VER:-1.20.1}"
DEST="${ORT_ROOT:-/tmp/onnxruntime-linux-x64-${VER}}"
TGZ="${ORT_TGZ:-/tmp/onnxruntime-linux-x64-${VER}.tgz}"
URL="https://github.com/microsoft/onnxruntime/releases/download/v${VER}/onnxruntime-linux-x64-${VER}.tgz"

if [[ -f "${DEST}/lib/libonnxruntime.so.1" ]]; then
	echo "ORT already present: ${DEST}"
	exit 0
fi

curl -fsSL -o "$TGZ" "$URL"
rm -rf "$DEST"
tar -C "$(dirname "$DEST")" -xzf "$TGZ"
echo "ORT_ROOT=${DEST}"
