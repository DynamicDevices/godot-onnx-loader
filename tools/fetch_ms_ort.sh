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

mkdir -p "$(dirname "$DEST")"
TMPDIR_FETCH="${TMPDIR:-/tmp}"
case "$PLAT" in
win-*)
	ZIP="${ORT_ZIP:-${TMPDIR_FETCH}/${BASE}.zip}"
	URL="https://github.com/microsoft/onnxruntime/releases/download/v${VER}/${BASE}.zip"
	curl -fsSL -o "$ZIP" "$URL"
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
	curl -fsSL -o "$TGZ" "$URL"
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
