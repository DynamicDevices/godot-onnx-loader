#!/usr/bin/env python
"""Build OnnxLoader GDExtension (.so) — scons-only.

  git submodule update --init --recursive
  nix develop   # sets ORT_ROOT
  scons platform=linux target=template_debug
  scons smoke-csv

Our C/C++ sources: -Wall -Wextra -Werror.
godot-cpp submodule: custom.py (-Wno-unused-parameter); addon C++ also -Wno-unused-parameter for generated headers.
"""
import os
import sys

from SCons.Script import ARGUMENTS, Alias, Default, Dir, SConscript


def _find_ort_header(root):
    lib = os.environ.get("ORT_LIB", os.path.join(root, "lib"))
    inc_candidates = [
        os.path.join(root, "include"),
        os.path.join(root, "include", "onnxruntime"),
    ]
    for inc in inc_candidates:
        if os.path.isfile(os.path.join(inc, "onnxruntime_c_api.h")):
            return inc, lib
    return inc_candidates[0], lib


ORT_ROOT = ARGUMENTS.get("ort_root", os.environ.get("ORT_ROOT", ""))
if not ORT_ROOT or not os.path.isdir(ORT_ROOT):
    print(
        "ORT_ROOT / ort_root= must point at an ONNX Runtime prefix (include/ + lib/).\n"
        "  nix develop   # sets ORT_ROOT\n"
        "  scons platform=linux target=template_debug",
        file=sys.stderr,
    )
    sys.exit(1)

godot_cpp = Dir("godot-cpp")
if not godot_cpp.exists() or not os.listdir(str(godot_cpp.srcnode())):
    print("godot-cpp missing. Run: git submodule update --init --recursive", file=sys.stderr)
    sys.exit(1)

env = SConscript("godot-cpp/SConstruct")

ort_inc, ort_lib = _find_ort_header(ORT_ROOT)
if not os.path.isfile(os.path.join(ort_inc, "onnxruntime_c_api.h")):
    print(f"ERROR: onnxruntime_c_api.h not found under ORT_ROOT={ORT_ROOT}", file=sys.stderr)
    sys.exit(1)

addon_src = "addons/onnx_loader/src"
runtime_c = [f"{addon_src}/onnx_runtime.c"]
godot_sources = [
    f"{addon_src}/OnnxLoader.cpp",
    f"{addon_src}/register_types.cpp",
]

# GDExtension: dlopen bundled ORT at runtime — do NOT link libonnxruntime into the
# .so (NEEDED + dlopen = two ORT instances → ReleaseSession heap crash under Godot).
ort_inc_flags = {
    "CPPDEFINES": {"ONNX_LOADER_WITH_ORT": 1},
    "CPPPATH": [addon_src, ort_inc],
}

smoke_link_flags = {
    "LIBPATH": [ort_lib],
    "LINKFLAGS": [
        "-Wl,--disable-new-dtags,-rpath,$ORIGIN",
        "-Wl,-z,noexecstack",
    ],
}

# C only — no godot headers; strict warnings.
env_c = env.Clone()
env_c.Append(
    CCFLAGS=["-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC"],
    **ort_inc_flags,
)

# C++ GDExtension bindings — Werror on our code; suppress godot-cpp header noise.
env_cpp = env.Clone()
env_cpp.Append(
    CXXFLAGS=["-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-Wno-unused-variable", "-fno-gnu-unique"],
    **ort_inc_flags,
    LINKFLAGS=["-Wl,-z,noexecstack"],
)
# Portable Linux .so — same pattern as godot_openxr_vendors / webrtc-native.
if env_cpp["platform"] == "linux":
    env_cpp.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++"])

runtime_lib = env_c.StaticLibrary("build/libonnx_runtime", runtime_c)

# Append addon libs; do not pass LIBS= to SharedLibrary (that drops libgodot-cpp).
env_cpp.Append(LIBS=[runtime_lib, "m", "dl"])

libname = "onnx_loader"
if env_cpp["platform"] == "macos":
    library = env_cpp.SharedLibrary(
        "addons/onnx_loader/bin/lib{}.{}.{}.framework/lib{}.{}.{}".format(
            libname,
            env_cpp["platform"],
            env_cpp["target"],
            libname,
            env_cpp["platform"],
            env_cpp["target"],
        ),
        source=godot_sources,
    )
else:
    library = env_cpp.SharedLibrary(
        "addons/onnx_loader/bin/lib{}{}{}".format(
            libname, env_cpp["suffix"], env_cpp["SHLIBSUFFIX"]
        ),
        source=godot_sources,
    )

smoke_csv = env_c.Program(
    "build/smoke_csv",
    "tools/smoke_csv.c",
    LIBS=[runtime_lib, "stdc++", "m", "dl"],
    **smoke_link_flags,
)

smoke_dlopen = env_c.Program(
    "build/smoke_dlopen_ort",
    "tools/smoke_dlopen_ort.c",
    LIBS=["stdc++", "dl"],
    **smoke_link_flags,
)

_wrap = "bash tools/with_bundled_ort.sh"


def _bundle_ort_libs(target, source, env):
    import shutil
    import stat

    if os.environ.get("ORT_BUNDLE", "1") == "0":
        print("ORT_BUNDLE=0 — skip copying libonnxruntime (use ONNX_ORT_BIN / store ORT)")
        stamp = Dir("addons/onnx_loader/bin").abspath
        os.makedirs(stamp, exist_ok=True)
        open(os.path.join(stamp, ".ort-bundled.stamp"), "w").close()
        return None

    dest_dir = Dir("addons/onnx_loader/bin").abspath
    os.makedirs(dest_dir, exist_ok=True)
    for name in ("libonnxruntime.so.1", "libonnxruntime.so"):
        src = os.path.join(ort_lib, name)
        if not os.path.isfile(src):
            continue
        dest = os.path.join(dest_dir, name)
        tmp = dest + ".new"
        shutil.copy2(src, tmp)
        os.chmod(
            tmp,
            stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH,
        )
        os.replace(tmp, dest)
    so1 = os.path.join(dest_dir, "libonnxruntime.so.1")
    if not os.path.isfile(so1):
        raise RuntimeError(
            f"ORT_BUNDLE=1 but {so1} missing after copy (ORT_ROOT={os.environ.get('ORT_ROOT', '')})"
        )
    return None


bundle_ort = env.Command(
    "addons/onnx_loader/bin/.ort-bundled.stamp",
    library,
    _bundle_ort_libs,
)

csv_path = "fixtures/ci-smoke/demo_inputs.csv"
model_onnx = "fixtures/ci-smoke/model.onnx"
smoke_csv_run = env_c.Command(
    "build/smoke_csv.stamp",
    [smoke_csv, bundle_ort, csv_path],
    f"{_wrap} ./build/smoke_csv fixtures/ci-smoke/model.json "
    "fixtures/ci-smoke/model.onnx "
    f"{csv_path} | tee /tmp/onnx-loader-smoke-csv.txt && "
    "grep -q ONNX_LOADER_CSV_SMOKE_OK /tmp/onnx-loader-smoke-csv.txt",
)

smoke_dlopen_run = env_c.Command(
    "build/smoke_dlopen_ort.stamp",
    [smoke_dlopen, bundle_ort, model_onnx],
    f"{_wrap} ./build/smoke_dlopen_ort "
    f'"{os.environ.get("ONNX_ORT_BIN", "addons/onnx_loader/bin")}" '
    "fixtures/ci-smoke/model.onnx | tee /tmp/onnx-loader-smoke-dlopen.txt && "
    "grep -q ONNX_DLOPEN_TEARDOWN_OK /tmp/onnx-loader-smoke-dlopen.txt",
)

Alias("smoke-csv", smoke_csv_run)
Alias("smoke-dlopen-ort", smoke_dlopen_run)
Alias("bundle-ort", bundle_ort)
Default(library, bundle_ort)
