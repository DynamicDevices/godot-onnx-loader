# OnnxLoader (Godot 4.6+)

**This zip:** prebuilt GDExtension + Microsoft ONNX Runtime 1.20.1 for
Godot 4.6+. Copy this entire directory to `res://addons/onnx_loader/`. The
`.gdextension` is discovered automatically; no plugin toggle or autoload is
required. Keep `bin/` beside it. Use the `OnnxLoader` class from GDScript — no env vars required
(ORT is loaded from `bin/` beside this addon).

```gdscript
var loader := OnnxLoader.new()
loader.load_model("res://model.onnx")
var out: PackedFloat32Array = loader.predict(inputs)
```

For multi-input/output models use persistent named bindings:
`set_input(name, data, shape)`, `run(output_names)`, then `get_output(name)`.
The existing `predict()` calls remain available for simple models.

```gdscript
var model := OnnxLoader.new()
assert(model.load_model("res://model.onnx"))
print(model.get_input_descriptors())
assert(model.set_input("features", values, PackedInt64Array([1, values.size()])))
assert(model.run())
var result := model.get_output("scores")
```

Every required named input must be bound before `run()`. Bindings persist until
replaced or a different model is loaded. After a failure, inspect
`get_last_error()`; output getters never return stale results from an earlier run.

Multi-platform zips include Linux, Windows, and macOS binaries. Linux-only zips
are smaller. NixOS users: prefer building from the git repo
(`tools/godot_46_nix_store_ort.sh`) if the glibc prebuild does not match your Godot.

Source / issues: https://github.com/DynamicDevices/godot-onnx-loader

## Layout

This folder is the **ship unit** (`.gdextension` + `bin/` + deps). C/C++ sources live at repo-root `src/` and are not required by consumers.
