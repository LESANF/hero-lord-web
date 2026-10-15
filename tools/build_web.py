#!/usr/bin/env python3
"""Assemble the browser build: official Godot 4.6 web template + web/index.html + the PCK.

usage: python3 -I tools/build_web.py build/web [path/to/web_nothreads_release.zip]

Without a local template zip, the ~10 MB member is read straight out of the
1.2 GB official export-templates archive on GitHub with HTTP range requests.
Expects build/web/hero-lord.pck to exist already (see pack_pck.py).
"""
from __future__ import annotations

import hashlib
import io
import json
import pathlib
import sys
import urllib.request
import zipfile

TPZ_URL = "https://github.com/godotengine/godot-builds/releases/download/4.6-stable/Godot_v4.6-stable_export_templates.tpz"
TEMPLATE_MEMBER = "templates/web_nothreads_release.zip"
TEMPLATE_SHA256 = "25d12ed1dda42fe4d863d6bd78075d632b41401afb085947bb4d3865a341fd90"
RUNTIME_FILES = ("godot.js", "godot.wasm", "godot.audio.worklet.js", "godot.audio.position.worklet.js")
ROOT = pathlib.Path(__file__).resolve().parent.parent


class RangeFile(io.RawIOBase):
    """Read-only seekable file over HTTP(S) using Range requests. Enough for zipfile."""

    def __init__(self, url: str):
        self.url, self.pos = url, 0
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as r:
            self.size = int(r.headers["Content-Length"])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=io.SEEK_SET):
        self.pos = {io.SEEK_SET: 0, io.SEEK_CUR: self.pos, io.SEEK_END: self.size}[whence] + offset
        return self.pos

    def read(self, n=-1):
        if n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + n - 1}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.pos += len(data)
        return data

    def readinto(self, b):
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


def template_zip(local: str | None) -> bytes:
    if local:
        data = pathlib.Path(local).read_bytes()
    else:
        with zipfile.ZipFile(RangeFile(TPZ_URL)) as tpz:
            data = tpz.read(TEMPLATE_MEMBER)
    digest = hashlib.sha256(data).hexdigest()
    if digest != TEMPLATE_SHA256:
        raise SystemExit(f"template zip sha256 mismatch: {digest}")
    return data


def main(out: str, local_template: str | None = None) -> None:
    out_dir = pathlib.Path(out)
    out_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(template_zip(local_template))) as z:
        for name in RUNTIME_FILES:
            (out_dir / name).write_bytes(z.read(name))
    sizes = {p.name: p.stat().st_size for p in out_dir.iterdir() if p.suffix in (".pck", ".wasm")}
    html = (ROOT / "web" / "index.html").read_text().replace("__FILE_SIZES__", json.dumps(sizes))
    (out_dir / "index.html").write_text(html)
    for p in sorted(out_dir.iterdir()):
        print(f"{p.stat().st_size:>12} {p.name}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
