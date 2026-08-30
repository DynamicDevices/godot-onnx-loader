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
        # Portable bundled releases cannot assume a host C++ runtime. A Nix-native
        # build instead shares the store libstdc++ used by Godot and ORT, avoiding
        # a second C++ runtime and cross-runtime symbol/allocator interposition.
        if os.environ.get("ORT_BUNDLE", "1") != "0":
            env_cpp.Append(LINKFLAGS=["-static-libgcc", "-static-libstdc++"])

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

# Host smokes: CSV through onnx_runtime (all platforms). dlopen ORT probe is Unix-only.
_smoke_out = os.path.join(Dir("build").abspath, "smoke-out")
os.makedirs(_smoke_out, exist_ok=True)
_csv_log = os.path.join(_smoke_out, "smoke-csv.txt").replace("\\", "/")
_dlopen_log = os.path.join(_smoke_out, "smoke-dlopen.txt").replace("\\", "/")
_wrap = "bash tools/with_bundled_ort.sh"
csv_path = "fixtures/ci-smoke/demo_inputs.csv"
model_onnx = "fixtures/ci-smoke/model.onnx"

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
