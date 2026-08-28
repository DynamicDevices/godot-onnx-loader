# OnnxLoader (Godot 4.6+)

GDExtension that runs ONNX models via Microsoft ONNX Runtime 1.20.1.

**This zip:** Linux x86_64 only (debug + release templates). Copy
`addons/onnx_loader` into your Godot project, enable the extension if needed,
then use the `OnnxLoader` class from GDScript.

```gdscript
var loader := OnnxLoader.new()
loader.load_model("res://model.onnx")
var out: PackedFloat32Array = loader.predict(inputs)
```

Source / issues: https://github.com/DynamicDevices/godot-onnx-loader

NixOS users: prefer building from the git repo (`tools/godot_46_ms_ort.sh`) —
this prebuilt glibc zip may not match a Nix Godot FHS wrapper.
