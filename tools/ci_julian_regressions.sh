#!/usr/bin/env bash
# CI regressions for failures Julian hit that stock MS ORT / happy-path CI missed.
# 1) glibc 2.41+ execstack on bundled ORT
# 2) smoke-csv with no ONNX_ORT_BIN and no bundled .so must fail clearly
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ORT_SO="${1:-$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1}"
CLEAR=(python3 "$ROOT/tools/clear_ort_execstack.py")
BAK="${ORT_SO}.bak-ci"

if [[ ! -f "$ORT_SO" ]]; then
	echo "ci_julian_regressions: missing $ORT_SO (build+bundle first)" >&2
	exit 1
fi
if [[ ! -x ./build/smoke_dlopen_ort ]]; then
	echo "ci_julian_regressions: build smoke_dlopen_ort first" >&2
	exit 1
fi

cp -a "$ORT_SO" "$BAK"
restore() { cp -a "$BAK" "$ORT_SO"; rm -f "$BAK"; }
trap restore EXIT

echo "=== regression: force RWE then clear + check (Julian execstack) ==="
"${CLEAR[@]}" --force-rwe "$ORT_SO"
if "${CLEAR[@]}" --check "$ORT_SO"; then
	echo "FAIL: --check should fail while RWE is set" >&2
	exit 1
fi
"${CLEAR[@]}" "$ORT_SO"
"${CLEAR[@]}" --check "$ORT_SO"

bash "$ROOT/tools/with_bundled_ort.sh" ./build/smoke_dlopen_ort \
	"$ROOT/addons/onnx_loader/bin" \
	fixtures/ci-smoke/model.onnx | tee /tmp/onnx-loader-julian-execstack.txt
grep -q ONNX_DLOPEN_TEARDOWN_OK /tmp/onnx-loader-julian-execstack.txt
if grep -q 'cannot enable executable stack' /tmp/onnx-loader-julian-execstack.txt; then
	echo "FAIL: executable stack error still present after clear" >&2
	exit 1
fi

echo "=== regression: missing ORT must fail clearly (Julian smoke-csv) ==="
rm -f "$ORT_SO"
set +e
env -u ONNX_ORT_BIN bash "$ROOT/tools/with_bundled_ort.sh" true >/tmp/onnx-loader-julian-missing-ort.txt 2>&1
rc=$?
set -e
cp -a "$BAK" "$ORT_SO"
if [[ "$rc" -eq 0 ]]; then
	echo "FAIL: with_bundled_ort should fail without ORT" >&2
	exit 1
fi
grep -q 'no ONNX_ORT_BIN and missing' /tmp/onnx-loader-julian-missing-ort.txt

"${CLEAR[@]}" --check "$ORT_SO"
trap - EXIT
rm -f "$BAK"

echo "=== regression: dynamic [batch,time,F] must load (TCN / Julian mid 951) ==="
bash "$ROOT/tools/smoke_dyn_create.sh"

echo JULIAN_CI_REGRESSIONS_OK
