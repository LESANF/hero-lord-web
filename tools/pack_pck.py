#!/usr/bin/env python3
"""Pack an exported Godot 4 project directory into a .pck.

Writes PCK format version 2 (what Godot 4.0-4.3 wrote and 4.4+ still reads),
stamped with the engine version the project was exported with.

usage: python3 -I tools/pack_pck.py build/project build/web/game.pck [4.6.0]
"""
import hashlib
import pathlib
import struct
import sys

MAGIC = b"GDPC"
FORMAT_VERSION = 2
ALIGN = 16


def _pad(n: int, align: int = ALIGN) -> int:
    return (-n) % align


def pack(src: str, dst: str, engine: str = "4.6.0") -> int:
    root = pathlib.Path(src)
    files = sorted(p for p in root.rglob("*") if p.is_file())
    major, minor, patch = (int(x) for x in engine.split("."))

    # pass 1: index
    entries = []
    ofs = 0
    for p in files:
        data = p.read_bytes()
        rel = ("res://" + p.relative_to(root).as_posix()).encode()
        entries.append((rel, ofs, len(data), hashlib.md5(data).digest()))
        ofs += len(data) + _pad(len(data))

    header = bytearray()
    header += MAGIC + struct.pack("<IIIII", FORMAT_VERSION, major, minor, patch, 0)
    file_base_at = len(header)
    header += struct.pack("<Q", 0) + b"\0" * (16 * 4)
    header += struct.pack("<I", len(entries))
    for rel, o, size, md5 in entries:
        rel_padded = rel + b"\0" * _pad(len(rel), 4)
        header += struct.pack("<I", len(rel_padded)) + rel_padded
        header += struct.pack("<QQ", o, size) + md5 + struct.pack("<I", 0)
    header += b"\0" * _pad(len(header))
    struct.pack_into("<Q", header, file_base_at, len(header))

    # pass 2: write
    out = pathlib.Path(dst)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as f:
        f.write(header)
        for p in files:
            data = p.read_bytes()
            f.write(data)
            f.write(b"\0" * _pad(len(data)))
    return len(entries)


def read_index(pck: str) -> dict:
    """Parse a PCK header back: {res_path: (offset, size)} with absolute offsets."""
    with open(pck, "rb") as f:
        magic, version, major, minor, patch, flags = struct.unpack("<4sIIIII", f.read(24))
        assert magic == MAGIC and version == FORMAT_VERSION, (magic, version)
        (file_base,) = struct.unpack("<Q", f.read(8))
        f.read(16 * 4)
        (count,) = struct.unpack("<I", f.read(4))
        index = {}
        for _ in range(count):
            (n,) = struct.unpack("<I", f.read(4))
            path = f.read(n).rstrip(b"\0").decode()
            o, size = struct.unpack("<QQ", f.read(16))
            f.read(16 + 4)
            index[path] = (file_base + o, size)
    return index


if __name__ == "__main__":
    n = pack(*sys.argv[1:4])
    print(f"{n} files -> {sys.argv[2]} ({pathlib.Path(sys.argv[2]).stat().st_size / 1e6:.1f} MB)")
