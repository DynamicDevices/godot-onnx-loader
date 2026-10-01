#!/usr/bin/env bash
# Reproducible CPU-only ONNX Runtime build for plugin packaging.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORT_COMMIT="${ORT_COMMIT:-5630b081cd25e4eccc7516a652ff956e51676794}"
ORT_SOURCE="${ORT_SOURCE:-$ROOT/.ort-src/onnxruntime}"
ORT_INSTALL="${ORT_INSTALL:-$ROOT/.ort-source-install}"
ORT_TARGET="${ORT_TARGET:-host}"

if [[ ! -d "$ORT_SOURCE/.git" ]]; then
	git clone --filter=blob:none --no-checkout https://github.com/microsoft/onnxruntime.git "$ORT_SOURCE"
fi
git -C "$ORT_SOURCE" fetch --depth 1 origin "$ORT_COMMIT"
git -C "$ORT_SOURCE" checkout --detach "$ORT_COMMIT"
git -C "$ORT_SOURCE" submodule update --init --recursive --depth 1

common=(--config Release --parallel --build_shared_lib --skip_tests
	--compile_no_warning_as_error --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF)
case "$ORT_TARGET" in
	host)
		"$ORT_SOURCE/build.sh" "${common[@]}"
		;;
	macos-arm64)
		"$ORT_SOURCE/build.sh" "${common[@]}" --osx_arch arm64
		;;
	android-arm64)
		: "${ANDROID_HOME:?ANDROID_HOME is required}"
		: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is required}"
		"$ORT_SOURCE/build.sh" "${common[@]}" --android \
			--android_sdk_path "$ANDROID_HOME" --android_ndk_path "$ANDROID_NDK_HOME" \
			--android_abi arm64-v8a --android_api 29
		;;
	*) echo "unsupported ORT_TARGET=$ORT_TARGET" >&2; exit 2 ;;
esac

rm -rf "$ORT_INSTALL"
mkdir -p "$ORT_INSTALL/include" "$ORT_INSTALL/lib"
cp "$ORT_SOURCE/include/onnxruntime/core/session/onnxruntime_c_api.h" "$ORT_INSTALL/include/"
find "$ORT_SOURCE/build" \( -type f -o -type l \) \
	\( -name 'libonnxruntime.so*' -o -name 'libonnxruntime*.dylib' \) \
	-exec cp -P {} "$ORT_INSTALL/lib/" \;
test -f "$ORT_INSTALL/include/onnxruntime_c_api.h"
find "$ORT_INSTALL/lib" -type f -o -type l | grep -q onnxruntime
printf 'ORT_SOURCE_BUILD_OK commit=%s target=%s install=%s\n' \
	"$ORT_COMMIT" "$ORT_TARGET" "$ORT_INSTALL"
