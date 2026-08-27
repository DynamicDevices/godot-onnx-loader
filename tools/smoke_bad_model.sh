#!/usr/bin/env bash
# Host smoke: missing model path must fail cleanly (Julian 443).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${OUT:-/tmp/onnx-loader-smoke-bad-model.txt}"

test -x build/smoke_csv || scons platform=linux target=template_debug build/smoke_csv >/dev/null

if bash "$ROOT/tools/with_bundled_ort.sh" ./build/smoke_csv fixtures/ci-smoke/model.json \
	/no/such/model.onnx fixtures/ci-smoke/demo_inputs.csv >"$OUT" 2>&1; then
	echo "FAIL: expected smoke_csv to reject missing model" >&2
	exit 1
fi
grep -qE 'model not found|onnx_runtime_create failed' "$OUT"
bash "$ROOT/tools/check_glibc_free.sh" "$OUT"
echo "SMOKE_BAD_MODEL_OK"
