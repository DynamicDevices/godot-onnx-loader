#!/usr/bin/env python3
"""Clear / check / force PT_GNU_STACK PF_X on a shared object.

glibc 2.41+ rejects dlopen of libs with an executable stack:
  cannot enable executable stack as shared object requires: Invalid argument

Commands:
  clear_ort_execstack.py <lib.so>           # clear PF_X (default)
  clear_ort_execstack.py --check <lib.so>   # exit 1 if PF_X set (CI gate)
  clear_ort_execstack.py --force-rwe <lib.so>  # CI only: inject Julian failure mode
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

PT_GNU_STACK = 0x6474E551
PF_X = 1


def _phdrs(data: bytearray) -> tuple[int, int, int, str, int]:
    if data[:4] != b"\x7fELF":
        raise SystemExit("not ELF")
    ei_class = data[4]
    ei_data = data[5]
    if ei_data != 1:
        raise SystemExit("only little-endian ELF supported")
    if ei_class == 2:
        return (
            struct.unpack_from("<Q", data, 32)[0],
            struct.unpack_from("<H", data, 54)[0],
            struct.unpack_from("<H", data, 56)[0],
            "<I",
            4,
        )
    if ei_class == 1:
        return (
            struct.unpack_from("<I", data, 28)[0],
            struct.unpack_from("<H", data, 42)[0],
            struct.unpack_from("<H", data, 44)[0],
            "<I",
            24,
        )
    raise SystemExit(f"unknown ELF class {ei_class}")


def _gnu_stack_flags(data: bytearray) -> tuple[int, int] | None:
    e_phoff, e_phentsize, e_phnum, p_type_fmt, p_flags_off = _phdrs(data)
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(p_type_fmt, data, off)[0]
        if p_type != PT_GNU_STACK:
            continue
        flags_off = off + p_flags_off
        flags = struct.unpack_from("<I", data, flags_off)[0]
        return flags_off, flags
    return None


def has_execstack(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    found = _gnu_stack_flags(data)
    if found is None:
        return False
    _, flags = found
    return bool(flags & PF_X)


def clear_execstack(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    found = _gnu_stack_flags(data)
    if found is None:
        return False
    flags_off, flags = found
    if not (flags & PF_X):
        return False
    struct.pack_into("<I", data, flags_off, flags & ~PF_X)
    path.write_bytes(data)
    return True


def force_execstack(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    found = _gnu_stack_flags(data)
    if found is None:
        raise SystemExit(f"no PT_GNU_STACK in {path}")
    flags_off, flags = found
    if flags & PF_X:
        return False
    struct.pack_into("<I", data, flags_off, flags | PF_X)
    path.write_bytes(data)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", type=Path)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true", help="fail if executable stack set")
    g.add_argument("--force-rwe", action="store_true", help="CI: inject RWE for regression")
    args = ap.parse_args()
    path: Path = args.path
    if not path.is_file():
        print(f"missing: {path}", file=sys.stderr)
        return 1

    if args.check:
        if has_execstack(path):
            print(f"FAIL: executable stack still set on {path}", file=sys.stderr)
            return 1
        print(f"ONNX_ORT_NOEXECSTACK_CHECK_OK path={path}")
        return 0

    if args.force_rwe:
        changed = force_execstack(path)
        print(f"ONNX_ORT_FORCE_RWE_OK path={path} changed={int(changed)}")
        return 0

    changed = clear_execstack(path)
    print(f"ONNX_ORT_NOEXECSTACK_OK path={path} cleared={int(changed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
