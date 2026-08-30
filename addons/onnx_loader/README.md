# OnnxLoader (Godot 4.6+)

**This zip:** prebuilt GDExtension + Microsoft ONNX Runtime 1.20.1 for
Godot 4.6+. Copy `addons/onnx_loader` into your project and enable the extension
if needed. Use the `OnnxLoader` class from GDScript — no env vars required
(ORT is loaded from `bin/` beside this addon).

```gdscript
var loader := OnnxLoader.new()
loader.load_model("res://model.onnx")
var out: PackedFloat32Array = loader.predict(inputs)
```

Multi-platform zips include Linux, Windows, and macOS binaries. Linux-only zips
are smaller. NixOS users: prefer building from the git repo
(`tools/godot_46_nix_store_ort.sh`) if the glibc prebuild does not match your Godot.

Source / issues: https://github.com/DynamicDevices/godot-onnx-loader

## Layout

This folder is the **ship unit** (`.gdextension` + `bin/` + deps). C/C++ sources live at repo-root `src/` and are not required by consumers.
