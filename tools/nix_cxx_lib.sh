#!/usr/bin/env bash
# Resolve directory containing libstdc++.so.6 for patchelf on Nix (gcc-wrapper has no .../lib).
set -euo pipefail

resolve_nix_cxx_lib() {
	if [[ -n "${NIX_CXX_LIB:-}" && -d "${NIX_CXX_LIB}" ]]; then
		echo "$NIX_CXX_LIB"
		return 0
	fi
	if ! command -v g++ >/dev/null 2>&1; then
		return 1
	fi
	local so
	so="$(g++ -print-file-name=libstdc++.so.6 2>/dev/null || true)"
	if [[ -n "$so" && "$so" != "libstdc++.so.6" && -f "$so" ]]; then
		dirname "$so"
		return 0
	fi
	return 1
}
