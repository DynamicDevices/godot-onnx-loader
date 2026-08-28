#!/usr/bin/env bash
# Ensure ORT_ROOT points at a usable ONNX Runtime prefix (include/ + lib/).
# Prefer an existing ORT_ROOT; otherwise fetch MS ORT into /tmp via fetch_ms_ort.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${ORT_MS_VER:-1.20.1}"

has_ort() {
	local root="$1"
	[[ -f "${root}/include/onnxruntime_c_api.h" ]] || return 1
	[[ -f "${root}/lib/libonnxruntime.so.1" ]] \
		|| [[ -f "${root}/lib/libonnxruntime.dylib" ]] \
		|| [[ -f "${root}/lib/libonnxruntime.1.20.1.dylib" ]] \
		|| [[ -f "${root}/lib/onnxruntime.dll" ]]
}

if [[ -n "${ORT_ROOT:-}" ]] && has_ort "$ORT_ROOT"; then
	echo "$ORT_ROOT"
	exit 0
fi

# Common local layouts (fresh clone without nix develop).
for cand in \
	"/tmp/onnxruntime-linux-x64-${VER}" \
	"/tmp/onnxruntime-osx-arm64-${VER}" \
	"/tmp/onnxruntime-osx-x86_64-${VER}" \
	"/tmp/onnxruntime-win-x64-${VER}" \
	"$ROOT/.ort/onnxruntime-linux-x64-${VER}"; do
	if has_ort "$cand"; then
		echo "$cand"
		exit 0
	fi
done

bash "$ROOT/tools/fetch_ms_ort.sh" >/dev/null
# Re-detect after fetch (fetch prints ORT_ROOT=…)
if [[ -n "${ORT_ROOT:-}" ]] && has_ort "$ORT_ROOT"; then
	echo "$ORT_ROOT"
	exit 0
fi
for cand in /tmp/onnxruntime-*-"${VER}"; do
	if has_ort "$cand"; then
		echo "$cand"
		exit 0
	fi
done
echo "ensure_ort: fetch failed (no usable ORT under /tmp/onnxruntime-*-${VER})" >&2
exit 1
