#!/usr/bin/env bash
# Resolve gcc runtime dirs for patchelf / bundling on Nix (gcc-wrapper has no .../lib).
set -euo pipefail

_gcc_print_dir() {
	local name="$1"
	if ! command -v g++ >/dev/null 2>&1; then
		return 1
	fi
	local so
	so="$(g++ -print-file-name="$name" 2>/dev/null || true)"
	if [[ -n "$so" && "$so" != "$name" && -f "$so" ]]; then
		dirname "$so"
		return 0
	fi
	return 1
}

resolve_nix_cxx_lib() {
	if [[ -n "${NIX_CXX_LIB:-}" && -d "${NIX_CXX_LIB}" ]]; then
		echo "$NIX_CXX_LIB"
		return 0
	fi
	_gcc_print_dir "libstdc++.so.6"
}

resolve_nix_gcc_s_lib() {
	_gcc_print_dir "libgcc_s.so.1"
}
