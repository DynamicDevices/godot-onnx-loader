# Asset Library submit — multi-platform (Godot 4.6)

Submit at: https://godotengine.org/asset-library/asset/submit
(Needs your Godot / AssetLib login — agent cannot submit for you.)

Prefer the **multi-platform** zip once a release tag builds it
(`godot-onnx-loader-v*-assetlib.zip`). Linux-only remains as a smaller sibling.

## Fields

| Field | Value |
|-------|--------|
| **Title** | OnnxLoader |
| **Category** | Tools (or Scripts / Misc) |
| **Godot version** | 4.6 |
| **License** | MIT |
| **Download provider** | **Custom** |
| **Download URL** | `https://github.com/DynamicDevices/godot-onnx-loader/releases/download/<tag>/godot-onnx-loader-<tag>-assetlib.zip` |

Example after `v0.2.1`:
`https://github.com/DynamicDevices/godot-onnx-loader/releases/download/v0.2.1/godot-onnx-loader-v0.2.1-assetlib.zip`

## Description (paste)

```
GDExtension that runs ONNX models inside Godot 4.6+ via Microsoft ONNX Runtime 1.20.1 (bundled).

Install: unzip and copy addons/onnx_loader/ into your project (Linux, Windows, macOS). No scons or env vars required — ORT loads from the addon's bin/.

NixOS users should build from the git repo (tools/godot_46_ms_ort.sh) if the glibc prebuild does not match your Godot FHS wrapper.

Repo: https://github.com/DynamicDevices/godot-onnx-loader
```

## After submit

Update README Install section with the AssetLib page URL once the listing is public.
Review can take days.
