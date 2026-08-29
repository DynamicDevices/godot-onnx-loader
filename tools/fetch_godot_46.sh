#!/usr/bin/env bash
# Fetch official Godot 4.6.1 stable for this host into GODOT_CACHE (default .godot-ci/).
# Prints the binary path on stdout. Used by CI Windows/macOS Godot smokes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${GODOT_VER:-4.6.1-stable}"
CACHE="${GODOT_CACHE:-$ROOT/.godot-ci}"
mkdir -p "$CACHE"

os="$(uname -s 2>/dev/null || echo unknown)"
case "$os" in
Linux*)
	ASSET="Godot_v${VER}_linux.x86_64.zip"
	BIN_NAME="Godot_v${VER}_linux.x86_64"
	;;
Darwin*)
	ASSET="Godot_v${VER}_macos.universal.zip"
	BIN_NAME="Godot.app/Contents/MacOS/Godot"
	;;
MINGW* | MSYS* | CYGWIN*)
	ASSET="Godot_v${VER}_win64.exe.zip"
	BIN_NAME="Godot_v${VER}_win64.exe"
	;;
*)
	# GitHub Actions windows often reports MINGW via bash; also accept explicit override.
	if [[ -n "${GODOT_ASSET:-}" ]]; then
		ASSET="$GODOT_ASSET"
		BIN_NAME="${GODOT_BIN_NAME:?set GODOT_BIN_NAME with GODOT_ASSET}"
	else
		echo "fetch_godot_46: unsupported OS=$os (set GODOT_ASSET / GODOT_BIN_NAME)" >&2
		exit 1
	fi
	;;
esac

# Windows runners: uname is often MINGW — handled above. Force win zip when requested.
if [[ "${GODOT_FORCE_WIN:-}" == "1" ]]; then
	ASSET="Godot_v${VER}_win64.exe.zip"
	BIN_NAME="Godot_v${VER}_win64.exe"
fi

DEST="$CACHE/${BIN_NAME%%/*}"
MARKER="$CACHE/.${ASSET}.ok"
BIN_PATH="$CACHE/$BIN_NAME"

if [[ -x "$BIN_PATH" || -f "$BIN_PATH" ]]; then
	echo "$BIN_PATH"
	exit 0
fi

ZIP="$CACHE/$ASSET"
URL="https://github.com/godotengine/godot-builds/releases/download/${VER}/${ASSET}"
echo "fetch_godot_46: downloading $URL" >&2
if command -v curl >/dev/null 2>&1; then
	curl -fsSL -o "$ZIP" "$URL"
elif command -v wget >/dev/null 2>&1; then
	wget -q -O "$ZIP" "$URL"
else
	python3 -c "import urllib.request; urllib.request.urlretrieve('$URL', '$ZIP')"
fi

rm -rf "$CACHE/extract-$$"
mkdir -p "$CACHE/extract-$$"
unzip -q "$ZIP" -d "$CACHE/extract-$$"
# Flatten into CACHE
if [[ -d "$CACHE/extract-$$/Godot.app" ]]; then
	rm -rf "$CACHE/Godot.app"
	mv "$CACHE/extract-$$/Godot.app" "$CACHE/"
elif [[ -f "$CACHE/extract-$$/$BIN_NAME" ]]; then
	mv "$CACHE/extract-$$/$BIN_NAME" "$CACHE/"
else
	# win zip may place exe at top level with different casing
	found="$(find "$CACHE/extract-$$" -maxdepth 2 -type f \( -name 'Godot*.exe' -o -name 'Godot*' \) | head -1)"
	if [[ -z "$found" ]]; then
		echo "fetch_godot_46: could not find Godot binary in zip" >&2
		ls -laR "$CACHE/extract-$$" >&2 || true
		exit 1
	fi
	mv "$found" "$CACHE/$(basename "$found")"
	BIN_PATH="$CACHE/$(basename "$found")"
fi
rm -rf "$CACHE/extract-$$"
chmod +x "$BIN_PATH" 2>/dev/null || true
touch "$MARKER"
echo "$BIN_PATH"
