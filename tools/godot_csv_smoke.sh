#!/usr/bin/env bash
# Headless csv_smoke through Godot 4.6+ — matches onnx_loader.gdextension compatibility_minimum.
# Prefer an official 4.6 binary; do not silently use nix develop's Godot 4.5.
# For NixOS Godot 4.6 + MS ORT build+smoke in one shot: bash tools/godot_46_ms_ort.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-/tmp/godot-onnx-loader-csv-smoke.txt}"
ORT_BUNDLE="${ORT_BUNDLE:-1}"

_godot_major_minor() {
	# Prints e.g. 4.6 from "4.6.1.stable.official...." or empty on failure.
	local bin="$1"
	local ver
	ver="$("$bin" --version 2>/dev/null | head -n1 || true)"
	if [[ "$ver" =~ ^([0-9]+)\.([0-9]+) ]]; then
		echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
	fi
}

_godot_at_least_46() {
	local mm
	mm="$(_godot_major_minor "$1")"
	[[ -n "$mm" ]] || return 1
	local major="${mm%%.*}"
	local minor="${mm#*.}"
	[[ "$major" -gt 4 ]] || { [[ "$major" -eq 4 && "$minor" -ge 6 ]]; }
}

_pick_godot() {
	local candidates=()
	[[ -n "${GODOT_BIN:-}" ]] && candidates+=("$GODOT_BIN")
	[[ -n "${GODOT:-}" ]] && candidates+=("$GODOT")
	candidates+=(
		"${HOME}/Downloads/Godot_v4.6.1-stable_linux.x86_64"
		"${HOME}/Downloads/Godot_v4.6-stable_linux.x86_64"
		"${HOME}/Downloads/Godot_v4.6.1-stable_win64.exe"
		"${HOME}/Downloads/Godot_v4.6.1-stable_macos.universal/Godot.app/Contents/MacOS/Godot"
	)
	# CI / tools/fetch_godot_46.sh cache
	if [[ -x "$ROOT/tools/fetch_godot_46.sh" ]]; then
		:
	fi
	if [[ -f "$ROOT/.godot-ci/Godot_v4.6.1-stable_win64.exe" ]]; then
		candidates+=("$ROOT/.godot-ci/Godot_v4.6.1-stable_win64.exe")
	fi
	if [[ -x "$ROOT/.godot-ci/Godot.app/Contents/MacOS/Godot" ]]; then
		candidates+=("$ROOT/.godot-ci/Godot.app/Contents/MacOS/Godot")
	fi
	if [[ -x "$ROOT/.godot-ci/Godot_v4.6.1-stable_linux.x86_64" ]]; then
		candidates+=("$ROOT/.godot-ci/Godot_v4.6.1-stable_linux.x86_64")
	fi
	# Only after explicit 4.6 paths — PATH may be nix godot 4.5.
	if command -v godot4 >/dev/null 2>&1; then
		candidates+=("$(command -v godot4)")
	fi
	if command -v godot >/dev/null 2>&1; then
		candidates+=("$(command -v godot)")
	fi

	local c
	for c in "${candidates[@]}"; do
		[[ -n "$c" && -x "$c" ]] || continue
		if _godot_at_least_46 "$c"; then
			echo "$c"
			return 0
		fi
		echo "godot_csv_smoke: skip $c (need Godot 4.6+, got $(_godot_major_minor "$c" || echo unknown))" >&2
	done
	return 1
}

GODOT="$(_pick_godot)" || {
	echo "godot_csv_smoke: no Godot 4.6+ binary found." >&2
	echo "  Set GODOT_BIN to Godot 4.6+, or install e.g. ~/Downloads/Godot_v4.6.1-stable_linux.x86_64" >&2
	echo "  On NixOS with MS ORT: bash tools/godot_46_ms_ort.sh" >&2
	echo "  (nix develop's godot_4 is often 4.5.x and cannot load this addon.)" >&2
	exit 1
}
echo "godot_csv_smoke: using $GODOT ($(_godot_major_minor "$GODOT"))"

if [[ -z "${ONNX_ORT_BIN:-}" ]]; then
	ORT_ROOT="$(bash "$ROOT/tools/ensure_ort.sh")"
	export ORT_ROOT
fi
if [[ ! -f "${ORT_ROOT:-}/lib/libonnxruntime.so.1" && -z "${ONNX_ORT_BIN:-}" ]]; then
	echo "ORT_ROOT missing libonnxruntime.so.1 (set ORT_ROOT or nix develop)" >&2
	exit 1
fi
if [[ ! -f "$ROOT/demo/addons/onnx_loader/bin/libonnx_loader.linux.template_debug.x86_64.so" ]]; then
	echo "Build addon first: ORT_ROOT=$ORT_ROOT scons platform=linux target=template_debug" >&2
	exit 1
fi
if [[ "$ORT_BUNDLE" != "0" && ! -f "$ROOT/addons/onnx_loader/bin/libonnxruntime.so.1" ]]; then
	echo "Bundled ORT missing — rebuild: scons platform=linux target=template_debug" >&2
	exit 1
fi

# Nix store ORT: keep LD_LIBRARY_PATH from nix develop (protobuf/abseil deps).
# Bundled MS ORT: prefer dlopen path only — drop stray LD_LIBRARY_PATH on Godot.
if [[ -z "${ONNX_ORT_BIN:-}" ]]; then
	unset LD_LIBRARY_PATH
fi
bash "$ROOT/tools/ensure_demo_extension.sh"
cd "$ROOT/demo"
"$GODOT" --headless --path . --quit-after 1 res://csv_smoke.tscn 2>&1 | tee "$OUT"
grep -q GODOT_ONNX_CSV_SMOKE_OK "$OUT"
bash "$ROOT/tools/check_glibc_free.sh" "$OUT"
echo "GODOT_CSV_SMOKE_OK"
