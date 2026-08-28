#!/usr/bin/env bash
# Ensure ORT_ROOT points at a usable ONNX Runtime prefix (include/ + lib/).
# Prefer an existing ORT_ROOT; otherwise fetch MS linux-x64 1.20.1 into /tmp.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${ORT_MS_VER:-1.20.1}"
DEFAULT_DEST="/tmp/onnxruntime-linux-x64-${VER}"

if [[ -n "${ORT_ROOT:-}" && -f "${ORT_ROOT}/include/onnxruntime_c_api.h" ]]; then
	echo "$ORT_ROOT"
	exit 0
fi

# Common local layouts (fresh clone without nix develop).
for cand in "$DEFAULT_DEST" "$ROOT/.ort/onnxruntime-linux-x64-${VER}"; do
	if [[ -f "${cand}/include/onnxruntime_c_api.h" ]]; then
		echo "$cand"
		exit 0
	fi
done

export ORT_ROOT="$DEFAULT_DEST"
bash "$ROOT/tools/fetch_ms_ort.sh" >/dev/null
if [[ ! -f "${ORT_ROOT}/include/onnxruntime_c_api.h" ]]; then
	echo "ensure_ort: fetch failed (missing ${ORT_ROOT}/include/onnxruntime_c_api.h)" >&2
	exit 1
fi
echo "$ORT_ROOT"
