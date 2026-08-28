#!/usr/bin/env bash
# Fetch Microsoft ONNX Runtime CPU prebuild into ORT_ROOT.
# Set ORT_PLATFORM=linux-x64|osx-arm64|osx-x86_64|win-x64 or auto-detect.
set -euo pipefail
VER="${ORT_MS_VER:-1.20.1}"

detect_platform() {
	case "$(uname -s 2>/dev/null || echo unknown)" in
	Linux*) echo "linux-x64" ;;
	Darwin*)
		case "$(uname -m)" in
		arm64 | aarch64) echo "osx-arm64" ;;
		*) echo "osx-x86_64" ;;
		esac
		;;
	MINGW* | MSYS* | CYGWIN* | Windows_NT) echo "win-x64" ;;
	*)
		echo "fetch_ms_ort: set ORT_PLATFORM=linux-x64|osx-arm64|osx-x86_64|win-x64" >&2
		exit 1
		;;
	esac
}

PLAT="${ORT_PLATFORM:-$(detect_platform)}"
DEST="${ORT_ROOT:-/tmp/onnxruntime-${PLAT}-${VER}}"
BASE="onnxruntime-${PLAT}-${VER}"

marker_ok() {
	[[ -f "${DEST}/include/onnxruntime_c_api.h" ]] || return 1
	case "$PLAT" in
	linux-*) [[ -f "${DEST}/lib/libonnxruntime.so.1" ]] ;;
	osx-*) [[ -f "${DEST}/lib/libonnxruntime.dylib" ]] || [[ -f "${DEST}/lib/libonnxruntime.1.20.1.dylib" ]] ;;
	win-*) [[ -f "${DEST}/lib/onnxruntime.dll" ]] ;;
	*) return 1 ;;
	esac
}

if marker_ok; then
	echo "ORT already present: ${DEST}"
	exit 0
fi

# Host PATH on self-hosted NixOS runners often lacks curl; flake puts it in
# `nix develop` only. Prefer curl, then wget, then python3 urllib.
download() {
	local url="$1" dest="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$dest" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$dest" "$url"
	elif command -v python3 >/dev/null 2>&1; then
		python3 - "$url" "$dest" <<'PY'
import sys
import urllib.request

urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
PY
	else
		echo "fetch_ms_ort: need curl, wget, or python3 to download $url" >&2
		exit 127
	fi
}

mkdir -p "$(dirname "$DEST")"
TMPDIR_FETCH="${TMPDIR:-/tmp}"
case "$PLAT" in
win-*)
	ZIP="${ORT_ZIP:-${TMPDIR_FETCH}/${BASE}.zip}"
	URL="https://github.com/microsoft/onnxruntime/releases/download/v${VER}/${BASE}.zip"
	download "$URL" "$ZIP"
	rm -rf "$DEST"
	# zip may nest one directory
	EXTRACT="${TMPDIR_FETCH}/ort-extract-$$"
	rm -rf "$EXTRACT"
	mkdir -p "$EXTRACT"
	unzip -q "$ZIP" -d "$EXTRACT"
	INNER="$(find "$EXTRACT" -maxdepth 2 -type d -name "onnxruntime-*" | head -1)"
	if [[ -z "$INNER" ]]; then
		INNER="$EXTRACT"
	fi
	mv "$INNER" "$DEST"
	rm -rf "$EXTRACT"
	;;
*)
	TGZ="${ORT_TGZ:-${TMPDIR_FETCH}/${BASE}.tgz}"
	URL="https://github.com/microsoft/onnxruntime/releases/download/v${VER}/${BASE}.tgz"
	download "$URL" "$TGZ"
	rm -rf "$DEST"
	tar -C "$(dirname "$DEST")" -xzf "$TGZ"
	# tarball usually extracts as onnxruntime-$PLAT-$VER
	if [[ ! -d "$DEST" ]]; then
		echo "fetch_ms_ort: expected $DEST after extract" >&2
		exit 1
	fi
	;;
esac

if ! marker_ok; then
	echo "fetch_ms_ort: incomplete extract at $DEST" >&2
	exit 1
fi
echo "ORT_ROOT=${DEST}"
