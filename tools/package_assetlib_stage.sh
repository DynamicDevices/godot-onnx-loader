#!/usr/bin/env bash
# Stage whatever is already under addons/onnx_loader/ into AssetLib zips.
# Used by release.yml after linux/windows/macos build artifacts are merged.
#
# Outputs:
#   ZIP       — multi-platform (default …-assetlib.zip)
#   ZIP_LINUX — Linux-only sibling (default …-linux-x86_64.zip) when MAKE_LINUX_ZIP=1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_VER="${PKG_VER:-$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
OUT_DIR="${OUT_DIR:-/tmp/godot-onnx-loader-assetlib}"
ZIP="${ZIP:-/tmp/godot-onnx-loader-${PKG_VER}-assetlib.zip}"
ZIP_LINUX="${ZIP_LINUX:-/tmp/godot-onnx-loader-${PKG_VER}-linux-x86_64.zip}"
REQUIRE_MULTI="${REQUIRE_MULTI:-1}"
MAKE_LINUX_ZIP="${MAKE_LINUX_ZIP:-1}"

cd "$ROOT"
test -f addons/onnx_loader/onnx_loader.gdextension
test -f LICENSE

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/addons/onnx_loader"
cp -a addons/onnx_loader/onnx_loader.gdextension "$OUT_DIR/addons/onnx_loader/"
[[ -f addons/onnx_loader/onnx_loader.gdextension.uid ]] && \
	cp -a addons/onnx_loader/onnx_loader.gdextension.uid "$OUT_DIR/addons/onnx_loader/"
cp -a addons/onnx_loader/README.md "$OUT_DIR/addons/onnx_loader/"
cp -a LICENSE "$OUT_DIR/addons/onnx_loader/LICENSE"

if [[ -d addons/onnx_loader/bin ]]; then
	mkdir -p "$OUT_DIR/addons/onnx_loader/bin"
	cp -a addons/onnx_loader/bin/. "$OUT_DIR/addons/onnx_loader/bin/"
fi

BIN="$OUT_DIR/addons/onnx_loader/bin"
test -f "$BIN/libonnx_loader.linux.template_debug.x86_64.so"
test -f "$BIN/libonnx_loader.linux.template_release.x86_64.so"
test -f "$BIN/libonnxruntime.so.1"

if [[ "$REQUIRE_MULTI" == "1" ]]; then
	test -f "$BIN/libonnx_loader.windows.template_debug.x86_64.dll"
	test -f "$BIN/libonnx_loader.windows.template_release.x86_64.dll"
	test -f "$BIN/onnxruntime.dll"
	test -d "$BIN/libonnx_loader.macos.template_debug.framework"
	test -d "$BIN/libonnx_loader.macos.template_release.framework"
	test -f "$BIN/libonnxruntime.dylib"
fi

# Prefer Python zipfile — Info-ZIP can exit 1 on warnings and skip writing
# the sibling linux zip under set -e in CI.
zip_tree() {
	local src="$1" dest="$2" mode="$3"
	python3 - "$src" "$dest" "$mode" <<'PY'
import sys, zipfile
from pathlib import Path

src, dest, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if dest.exists():
    dest.unlink()

def keep(rel: str) -> bool:
    if mode == "all":
        return True
    if rel in (
        "addons/onnx_loader/onnx_loader.gdextension",
        "addons/onnx_loader/onnx_loader.gdextension.uid",
        "addons/onnx_loader/README.md",
        "addons/onnx_loader/LICENSE",
    ):
        return True
    return rel.startswith("addons/onnx_loader/bin/libonnx_loader.linux.") or rel.startswith(
        "addons/onnx_loader/bin/libonnxruntime.so"
    )

with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for p in sorted(src.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(src))
        if keep(rel):
            zf.write(p, arcname=rel)
print(f"wrote {dest} ({dest.stat().st_size} bytes)")
PY
}

zip_tree "$OUT_DIR" "$ZIP" all
test -f "$ZIP"
echo "ASSETLIB_PACKAGE_OK zip=$ZIP require_multi=$REQUIRE_MULTI"
ls -lh "$ZIP"

if [[ "$MAKE_LINUX_ZIP" == "1" ]]; then
	zip_tree "$OUT_DIR" "$ZIP_LINUX" linux
	test -f "$ZIP_LINUX"
	echo "ASSETLIB_LINUX_OK zip=$ZIP_LINUX"
	ls -lh "$ZIP_LINUX"
fi
