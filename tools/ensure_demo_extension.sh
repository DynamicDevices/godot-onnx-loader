#!/usr/bin/env bash
# Ensure demo/.godot/extension_list.cfg exists so headless Godot loads the addon.
# Do not commit .godot/ — Julian: editor cache stays local; smokes recreate this file.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_GODOT="$ROOT/demo/.godot"
EXT_LIST="$DEMO_GODOT/extension_list.cfg"
mkdir -p "$DEMO_GODOT"
printf '%s\n' 'res://addons/onnx_loader/onnx_loader.gdextension' >"$EXT_LIST"
# Keep Godot from treating this as a shared VCS cache if someone opens the editor.
touch "$DEMO_GODOT/.gdignore"
