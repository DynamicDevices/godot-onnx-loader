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

ort_flags = {
    "CPPDEFINES": {"ONNX_LOADER_WITH_ORT": 1},
    "LIBPATH": [ort_lib],
    "LIBS": ["onnxruntime", "m"],
    "LINKFLAGS": [f"-Wl,-rpath,{ort_lib}"],
}

# C only — no godot headers; strict warnings.
env_c = env.Clone()
env_c.Append(
    CPPPATH=[addon_src, ort_inc],
    CCFLAGS=["-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC"],
    **ort_flags,
)

# C++ GDExtension bindings — Werror on our code; suppress godot-cpp header noise.
env_cpp = env.Clone()
env_cpp.Append(
    CPPPATH=[addon_src, ort_inc],
    CXXFLAGS=["-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter"],
    **ort_flags,
)

runtime_lib = env_c.StaticLibrary("build/libonnx_runtime", runtime_c)

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
        LIBS=[runtime_lib, "onnxruntime", "m"],
    )
else:
    library = env_cpp.SharedLibrary(
        "addons/onnx_loader/bin/lib{}{}{}".format(
            libname, env_cpp["suffix"], env_cpp["SHLIBSUFFIX"]
        ),
        source=godot_sources,
        LIBS=[runtime_lib, "onnxruntime", "m"],
    )

smoke_csv = env_c.Program("build/smoke_csv", "tools/smoke_csv.c", LIBS=[runtime_lib, "onnxruntime", "m"])

csv_path = "fixtures/ci-smoke/demo_inputs.csv"
smoke_csv_run = env_c.Command(
    "build/smoke_csv.stamp",
    [smoke_csv, csv_path],
    "./build/smoke_csv fixtures/ci-smoke/model.json fixtures/ci-smoke/model.onnx "
    f"{csv_path} | tee /tmp/onnx-loader-smoke-csv.txt && "
    "grep -q ONNX_LOADER_CSV_SMOKE_OK /tmp/onnx-loader-smoke-csv.txt",
)

Alias("smoke-csv", smoke_csv_run)
Default(library)
