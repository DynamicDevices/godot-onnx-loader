#!/usr/bin/env python
"""Build OnnxLoader GDExtension — scons-only.

  git submodule update --init --recursive
  # Linux: nix develop or bash tools/fetch_ms_ort.sh
  scons platform=linux|windows|macos target=template_debug
  scons smoke-csv   # host CSV smoke (all platforms; needs ORT_BUNDLE)

Our C/C++ sources: -Wall -Wextra -Werror (GCC/Clang).
godot-cpp submodule: custom.py (-Wno-unused-parameter).
"""
import os
import sys

from SCons.Script import ARGUMENTS, Alias, AlwaysBuild, Default, Dir, SConscript


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


def _ensure_ort_root():
    """Resolve ORT_ROOT: env/arg, else tools/ensure_ort.sh (fetch MS ORT)."""
    root = ARGUMENTS.get("ort_root", os.environ.get("ORT_ROOT", ""))
    if root and os.path.isdir(root) and os.path.isfile(
        os.path.join(root, "include", "onnxruntime_c_api.h")
    ):
        return root
    if root and os.path.isdir(root):
        for sub in ("include", os.path.join("include", "onnxruntime")):
            if os.path.isfile(os.path.join(root, sub, "onnxruntime_c_api.h")):
                return root
    ensure = os.path.join(Dir(".").srcnode().abspath, "tools", "ensure_ort.sh")
    if not os.path.isfile(ensure):
        print(
            "ORT_ROOT unset and tools/ensure_ort.sh missing.\n"
            "  bash tools/fetch_ms_ort.sh && export ORT_ROOT=...",
            file=sys.stderr,
        )
        sys.exit(1)
    import subprocess

    print("ORT_ROOT unset — ensuring MS ONNX Runtime via tools/ensure_ort.sh", file=sys.stderr)
    out = subprocess.check_output(["bash", ensure], text=True).strip()
    if not out or not os.path.isdir(out):
        print(f"ensure_ort.sh returned unusable path: {out!r}", file=sys.stderr)
        sys.exit(1)
    os.environ["ORT_ROOT"] = out
    if "ORT_BUNDLE" not in os.environ:
        os.environ["ORT_BUNDLE"] = "1"
    print(f"ORT_ROOT={out}", file=sys.stderr)
    return out


ORT_ROOT = _ensure_ort_root()

godot_cpp = Dir("godot-cpp")
if not godot_cpp.exists() or not os.listdir(str(godot_cpp.srcnode())):
    print("godot-cpp missing. Run: git submodule update --init --recursive", file=sys.stderr)
    sys.exit(1)

env = SConscript("godot-cpp/SConstruct")

for _key in (
    "ONNX_ORT_BIN",
    "ORT_ROOT",
    "ORT_LIB",
    "ORT_BUNDLE",
    "LD_LIBRARY_PATH",
    "LIBRARY_PATH",
    "C_INCLUDE_PATH",
    "GODOT_BIN",
    "ONNX_LOADER_SKIP_SESSION_RELEASE",
    "PATH",
):
    if _key in os.environ and os.environ[_key]:
        env["ENV"][_key] = os.environ[_key]

ort_inc, ort_lib = _find_ort_header(ORT_ROOT)
if not os.path.isfile(os.path.join(ort_inc, "onnxruntime_c_api.h")):
    print(f"ERROR: onnxruntime_c_api.h not found under ORT_ROOT={ORT_ROOT}", file=sys.stderr)
    sys.exit(1)

platform = env["platform"]
is_windows = platform == "windows"
is_macos = platform == "macos"
is_linux = platform == "linux"

addon_src = "src"  # ship unit is addons/onnx_loader (bin + .gdextension only)
runtime_c = [f"{addon_src}/onnx_runtime.c"]
godot_sources = [
    f"{addon_src}/OnnxLoader.cpp",
    f"{addon_src}/register_types.cpp",
]

ort_inc_flags = {
    "CPPDEFINES": {"ONNX_LOADER_WITH_ORT": 1},
    "CPPPATH": [addon_src, ort_inc],
}

env_c = env.Clone()
env_cpp = env.Clone()
env_c.Append(**ort_inc_flags)
env_cpp.Append(**ort_inc_flags)

# Enforce one process-wide C++ runtime even if a caller's cached/default
# godot-cpp options requested its traditional portable static runtime.
env_cpp["LINKFLAGS"] = [
    flag
    for flag in env_cpp.get("LINKFLAGS", [])
    if flag not in ("-static-libgcc", "-static-libstdc++")
]

if is_windows:
    # MSVC / clang-cl: keep warnings reasonable; godot-cpp sets /std.
    env_c.Append(CFLAGS=["/W3"])
    env_cpp.Append(CXXFLAGS=["/W3"])
else:
    env_c.Append(
        CCFLAGS=[
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-unused-but-set-parameter",
            "-fPIC",
        ],
    )
    env_cpp.Append(
        CXXFLAGS=[
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-unused-parameter",
            "-Wno-unused-variable",
            "-Wno-unused-but-set-parameter",
        ],
    )
    if is_linux:
        # GCC-only; Apple clang rejects -fno-gnu-unique.
        env_cpp.Append(CXXFLAGS=["-fno-gnu-unique"])
        env_cpp.Append(LINKFLAGS=["-Wl,-z,noexecstack"])
        # A GDExtension and dynamically loaded ORT are one process-wide C++ ABI
        # system. Never embed another libstdc++/libgcc in the extension: exported
        # static-runtime symbols can interpose ORT's C++ implementation and make
        # objects allocated during session creation invalid at ReleaseSession.
        # Godot's Linux runtime already supplies the process C++ runtime; Nix
        # packages must build Godot, this extension and ORT from one package set.

runtime_lib = env_c.StaticLibrary("build/libonnx_runtime", runtime_c)

if is_windows:
    env_cpp.Append(LIBS=[runtime_lib])
else:
    env_cpp.Append(LIBS=[runtime_lib, "m", "dl"])

libname = "onnx_loader"
if is_macos:
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


def _bundle_ort_libs(target, source, env):
    import shutil
    import stat

    stamp = os.path.abspath(str(target[0]))
    os.makedirs(os.path.dirname(stamp), exist_ok=True)

    if os.environ.get("ORT_BUNDLE", "1") == "0":
        print("ORT_BUNDLE=0 — skip copying libonnxruntime (use ONNX_ORT_BIN / store ORT)")
        open(stamp, "w").close()
        return None

    dest_dir = Dir("addons/onnx_loader/bin").abspath
    os.makedirs(dest_dir, exist_ok=True)

    if is_windows:
        names = ("onnxruntime.dll",)
    elif is_macos:
        names = (
            "libonnxruntime.1.20.1.dylib",
            "libonnxruntime.dylib",
        )
    else:
        names = ("libonnxruntime.so.1", "libonnxruntime.so")

    copied = []
    for name in names:
        src = os.path.join(ort_lib, name)
        if not os.path.isfile(src):
            continue
        dest = os.path.join(dest_dir, name)
        tmp = dest + ".new"
        shutil.copy2(src, tmp)
        os.chmod(
            tmp,
            stat.S_IRUSR
            | stat.S_IWUSR
            | stat.S_IXUSR
            | stat.S_IRGRP
            | stat.S_IXGRP
            | stat.S_IROTH
            | stat.S_IXOTH,
        )
        os.replace(tmp, dest)
        copied.append(dest)

    if not copied:
        raise RuntimeError(
            f"ORT_BUNDLE=1 but no ORT shared lib copied from {ort_lib} (names={names})"
        )

    if is_macos:
        # .gdextension [dependencies] lists libonnxruntime.dylib — ensure that name
        # exists even when MS only ships the versioned dylib.
        plain = os.path.join(dest_dir, "libonnxruntime.dylib")
        if not os.path.isfile(plain):
            for ver in ("libonnxruntime.1.20.1.dylib", "libonnxruntime.1.dylib"):
                src_ver = os.path.join(dest_dir, ver)
                if os.path.isfile(src_ver):
                    shutil.copy2(src_ver, plain)
                    break
            if not os.path.isfile(plain):
                raise RuntimeError(
                    "ORT_BUNDLE=1 macos: need libonnxruntime.dylib beside the addon"
                )

    if is_linux:
        import subprocess

        so1 = os.path.join(dest_dir, "libonnxruntime.so.1")
        subprocess.check_call(["python3", "tools/clear_ort_execstack.py", so1])
        on_nix = os.path.isdir("/nix/store") or bool(os.environ.get("NIX_CXX_LIB"))
        if on_nix:
            patch_env = os.environ.copy()
            patch_env["REQUIRE_NIX_PATCH"] = "1"
            subprocess.check_call(
                ["bash", "tools/patch_bundled_ort_rpath.sh"],
                env=patch_env,
            )
            subprocess.check_call(["python3", "tools/clear_ort_execstack.py", "--check", so1])
    open(stamp, "w").close()
    return None


bundle_stamp = (
    "addons/onnx_loader/bin/.ort-store.stamp"
    if os.environ.get("ORT_BUNDLE", "1") == "0"
    else "addons/onnx_loader/bin/.ort-bundled.stamp"
)
bundle_ort = env.Command(
    bundle_stamp,
    library,
    _bundle_ort_libs,
)
# The shared libraries are side effects rather than SCons targets. A cached
# stamp alone is therefore insufficient in a fresh checkout; always restage
# the selected runtime after the (still cacheable) extension build.
AlwaysBuild(bundle_ort)
env.NoCache(bundle_ort)

# Host smokes: CSV through onnx_runtime (all platforms). dlopen ORT probe is Unix-only.
_smoke_out = os.path.join(Dir("build").abspath, "smoke-out")
os.makedirs(_smoke_out, exist_ok=True)
_csv_log = os.path.join(_smoke_out, "smoke-csv.txt").replace("\\", "/")
_dlopen_log = os.path.join(_smoke_out, "smoke-dlopen.txt").replace("\\", "/")
_wrap = "bash tools/with_bundled_ort.sh"
csv_path = "fixtures/ci-smoke/demo_inputs.csv"
model_onnx = "fixtures/ci-smoke/model.onnx"
temporal_model_onnx = "fixtures/hardening/temporal_pose.onnx"

# Host tools must not use godot-cpp's macos universal (-arch arm64 -arch x86_64):
# MS ORT is single-arch and dual-arch link drops _main for one slice.
env_smoke = env_c.Clone()
if is_macos:
    import platform as _pyplat

    _host_arch = "arm64" if _pyplat.machine() == "arm64" else "x86_64"

    def _drop_arch_flags(flags):
        out = []
        skip = False
        for f in list(flags or []):
            if skip:
                skip = False
                continue
            if f == "-arch":
                skip = True
                continue
            out.append(f)
        return out

    for _k in ("CCFLAGS", "CFLAGS", "CXXFLAGS", "LINKFLAGS", "ASFLAGS"):
        if _k in env_smoke:
            env_smoke[_k] = _drop_arch_flags(env_smoke[_k])
    env_smoke.Append(CCFLAGS=["-arch", _host_arch], LINKFLAGS=["-arch", _host_arch])

if is_windows:
    smoke_csv = env_smoke.Program(
        "build/smoke_csv",
        "tools/smoke_csv.c",
        LIBS=[runtime_lib],
    )
else:
    smoke_link_flags = {
        "LIBPATH": [ort_lib],
        "LINKFLAGS": [
            "-Wl,-rpath,$ORIGIN",
        ],
    }
    if is_linux:
        smoke_link_flags["LINKFLAGS"] = [
            "-Wl,--disable-new-dtags,-rpath,$ORIGIN",
            "-Wl,-z,noexecstack",
        ]
    elif is_macos:
        smoke_link_flags["LINKFLAGS"] = ["-Wl,-rpath,@loader_path"]
    smoke_csv = env_smoke.Program(
        "build/smoke_csv",
        "tools/smoke_csv.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )

smoke_csv_exe = str(smoke_csv[0]).replace("\\", "/")
smoke_csv_run = env_smoke.Command(
    "build/smoke_csv.stamp",
    [smoke_csv, bundle_ort, csv_path],
    f"{_wrap} {smoke_csv_exe} fixtures/ci-smoke/model.json "
    "fixtures/ci-smoke/model.onnx "
    f"{csv_path} > {_csv_log} 2>&1 && "
    f"grep -q ONNX_LOADER_CSV_SMOKE_OK {_csv_log} && "
    f"cat {_csv_log}",
)
Alias("smoke-csv", smoke_csv_run)

if not is_windows:
    temporal_fixture_smoke = env_smoke.Program(
        "build/temporal_fixture_smoke",
        "tools/temporal_fixture_smoke.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )
    temporal_fixture_exe = str(temporal_fixture_smoke[0]).replace("\\", "/")
    temporal_fixture_run = env_smoke.Command(
        "build/temporal_fixture_smoke.stamp",
        [temporal_fixture_smoke, bundle_ort, temporal_model_onnx],
        f"{_wrap} {temporal_fixture_exe} {temporal_model_onnx} | "
        "tee build/smoke-out/temporal-fixture.txt && "
        "grep -q ONNX_TEMPORAL_FIXTURE_OK build/smoke-out/temporal-fixture.txt",
    )
    Alias("smoke-temporal-fixture", temporal_fixture_run)

    type_fixture_models = [
        f"fixtures/hardening/types/{name}.onnx"
        for name in ("float16", "float64", "int32", "int64", "bool")
    ]
    type_rejection_smoke = env_smoke.Program(
        "build/type_rejection_smoke",
        "tools/type_rejection_smoke.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )
    type_rejection_exe = str(type_rejection_smoke[0]).replace("\\", "/")
    type_rejection_run = env_smoke.Command(
        "build/type_rejection_smoke.stamp",
        [type_rejection_smoke, bundle_ort] + type_fixture_models,
        f"{_wrap} {type_rejection_exe} {' '.join(type_fixture_models)} | "
        "tee build/smoke-out/type-rejections.txt && "
        "grep -c ONNX_TYPE_REJECTION_OK build/smoke-out/type-rejections.txt | grep -qx 5",
    )
    Alias("smoke-type-rejections", type_rejection_run)

    failure_fixture_models = [
        "fixtures/hardening/malformed.onnx",
        "fixtures/hardening/unsupported_operator.onnx",
    ]
    load_failure_smoke = env_smoke.Program(
        "build/load_failure_smoke",
        "tools/load_failure_smoke.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )
    load_failure_exe = str(load_failure_smoke[0]).replace("\\", "/")
    load_failure_run = env_smoke.Command(
        "build/load_failure_smoke.stamp",
        [load_failure_smoke, bundle_ort] + failure_fixture_models,
        f"{_wrap} {load_failure_exe} {' '.join(failure_fixture_models)} | "
        "tee build/smoke-out/load-failures.txt && "
        "grep -c ONNX_LOAD_FAILURE_OK build/smoke-out/load-failures.txt | grep -qx 3",
    )
    Alias("smoke-load-failures", load_failure_run)

    shape_fixture_models = [
        "fixtures/hardening/scalar.onnx",
        "fixtures/hardening/multi_dynamic.onnx",
        "fixtures/hardening/multi_output.onnx",
    ]
    shape_edges_smoke = env_smoke.Program(
        "build/shape_edges_smoke",
        "tools/shape_edges_smoke.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )
    shape_edges_exe = str(shape_edges_smoke[0]).replace("\\", "/")
    shape_edges_run = env_smoke.Command(
        "build/shape_edges_smoke.stamp",
        [shape_edges_smoke, bundle_ort] + shape_fixture_models,
        f"{_wrap} {shape_edges_exe} {' '.join(shape_fixture_models)} | "
        "tee build/smoke-out/shape-edges.txt && "
        "grep -q ONNX_SHAPE_EDGES_OK build/smoke-out/shape-edges.txt",
    )
    Alias("smoke-shape-edges", shape_edges_run)

if not is_windows:
    session_stress = env_smoke.Program(
        "build/session_stress",
        "tools/session_stress.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )
    session_stress_exe = str(session_stress[0]).replace("\\", "/")
    session_stress_run = env_smoke.Command(
        "build/session_stress.stamp",
        [session_stress, bundle_ort, model_onnx],
        f"{_wrap} {session_stress_exe} {model_onnx} | tee build/smoke-out/session-stress.txt && "
        "grep -q ONNX_SESSION_STRESS_OK build/smoke-out/session-stress.txt",
    )
    Alias("stress-sessions", session_stress_run)

    benchmark_env = env_smoke.Clone()
    benchmark_env.Append(CPPDEFINES=["ONNX_LOADER_HAS_REUSE_DIAGNOSTICS"])
    inference_benchmark = benchmark_env.Program(
        "build/inference_benchmark",
        "tools/inference_benchmark.c",
        LIBS=[runtime_lib, "stdc++", "m", "dl"],
        **smoke_link_flags,
    )
    benchmark_exe = str(inference_benchmark[0]).replace("\\", "/")
    benchmark_run = benchmark_env.Command(
        "build/inference_benchmark.stamp",
        [inference_benchmark, bundle_ort, model_onnx],
        f"{_wrap} {benchmark_exe} {model_onnx} | "
        "tee build/smoke-out/inference-benchmark.txt && "
        "grep -q ONNX_INFERENCE_BENCHMARK_OK build/smoke-out/inference-benchmark.txt",
    )
    Alias("benchmark-inference", benchmark_run)

if not is_windows:
    smoke_dlopen = env_smoke.Program(
        "build/smoke_dlopen_ort",
        "tools/smoke_dlopen_ort.c",
        LIBS=["stdc++", "dl"],
        **(
            {
                "LIBPATH": [ort_lib],
                "LINKFLAGS": (
                    ["-Wl,--disable-new-dtags,-rpath,$ORIGIN", "-Wl,-z,noexecstack"]
                    if is_linux
                    else ["-Wl,-rpath,@loader_path"]
                ),
            }
        ),
    )
    smoke_dlopen_run = env_smoke.Command(
        "build/smoke_dlopen_ort.stamp",
        [smoke_dlopen, bundle_ort, model_onnx],
        f"{_wrap} ./build/smoke_dlopen_ort "
        f'"{os.environ.get("ONNX_ORT_BIN", "addons/onnx_loader/bin")}" '
        f"fixtures/ci-smoke/model.onnx > {_dlopen_log} 2>&1 && "
        f"grep -q ONNX_DLOPEN_TEARDOWN_OK {_dlopen_log} && "
        f"cat {_dlopen_log}",
    )
    Alias("smoke-dlopen-ort", smoke_dlopen_run)

Alias("bundle-ort", bundle_ort)
Default(library, bundle_ort)
