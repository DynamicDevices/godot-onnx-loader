#!/usr/bin/env bash
# Fail CI if Godot/csv_smoke output shows glibc heap abort markers.
set -euo pipefail
LOG="${1:?usage: check_glibc_free.sh <log>}"
if grep -qE 'free\(\): invalid (size|pointer)' "$LOG"; then
	echo "FAIL: glibc free() error in $LOG" >&2
	grep -E 'free\(\): invalid|Aborted|ONNX_LOADER_TEARDOWN' "$LOG" >&2 || true
	exit 1
fi
if grep -q 'Aborted (core dumped)' "$LOG"; then
	echo "FAIL: process aborted in $LOG" >&2
	exit 1
fi
