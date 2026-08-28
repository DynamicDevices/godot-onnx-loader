#!/usr/bin/env python3
"""Clear PT_GNU_STACK PF_X on a shared object (glibc 2.41+ rejects execstack).

MS ORT / some vendor .so files still advertise an executable stack. dlopen then
fails with: cannot enable executable stack as shared object requires.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

PT_GNU_STACK = 0x6474E551
PF_X = 1


def clear_execstack(path: Path) -> bool:
    data = bytearray(path.read_bytes())
    if data[:4] != b"\x7fELF":
        raise SystemExit(f"not ELF: {path}")
    ei_class = data[4]  # 1=32, 2=64
    ei_data = data[5]  # 1=LE, 2=BE
    if ei_data != 1:
        raise SystemExit(f"only little-endian ELF supported: {path}")
    if ei_class == 2:
        e_phoff = struct.unpack_from("<Q", data, 32)[0]
        e_phentsize = struct.unpack_from("<H", data, 54)[0]
        e_phnum = struct.unpack_from("<H", data, 56)[0]
        p_type_fmt, p_flags_off = "<I", 4
    elif ei_class == 1:
        e_phoff = struct.unpack_from("<I", data, 28)[0]
        e_phentsize = struct.unpack_from("<H", data, 42)[0]
        e_phnum = struct.unpack_from("<H", data, 44)[0]
        p_type_fmt, p_flags_off = "<I", 24
    else:
        raise SystemExit(f"unknown ELF class {ei_class}: {path}")

    changed = False
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(p_type_fmt, data, off)[0]
        if p_type != PT_GNU_STACK:
            continue
        flags_off = off + p_flags_off
        flags = struct.unpack_from("<I", data, flags_off)[0]
        if flags & PF_X:
            struct.pack_into("<I", data, flags_off, flags & ~PF_X)
            changed = True
        break
    if changed:
        path.write_bytes(data)
    return changed


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <lib.so>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"missing: {path}", file=sys.stderr)
        return 1
    changed = clear_execstack(path)
    print(f"ONNX_ORT_NOEXECSTACK_OK path={path} cleared={int(changed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
