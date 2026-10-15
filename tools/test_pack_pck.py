#!/usr/bin/env python3
"""Round-trip check for pack_pck: python3 -I tools/test_pack_pck.py"""
import pathlib
import struct
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import pack_pck  # noqa: E402

with tempfile.TemporaryDirectory() as tmp:
    src = pathlib.Path(tmp, "proj")
    # path lengths 10/11/12/13 bytes after "res://" to exercise every string padding case
    samples = {
        "a.txt": b"hello",
        "ab.txt": b"",
        ".godot/x.ctex": bytes(range(256)) * 3,
        "deep/er/file.gdc": b"GDSC" + b"\x01" * 37,
    }
    for rel, data in samples.items():
        p = src / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    pck = pathlib.Path(tmp, "out.pck")
    assert pack_pck.pack(str(src), str(pck), "4.6.0") == len(samples)

    raw = pck.read_bytes()
    assert raw[:4] == b"GDPC"
    assert struct.unpack_from("<IIII", raw, 4) == (2, 4, 6, 0)

    index = pack_pck.read_index(str(pck))
    assert set(index) == {"res://" + k for k in samples}, index
    for rel, data in samples.items():
        off, size = index["res://" + rel]
        assert size == len(data)
        assert off % pack_pck.ALIGN == 0, (rel, off)
        assert raw[off:off + size] == data, rel
    print("ok", len(samples), "files,", len(raw), "bytes")
