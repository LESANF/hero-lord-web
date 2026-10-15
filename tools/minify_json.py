#!/usr/bin/env python3
"""Strip whitespace from every .json under a directory, in place (halves the game data).

usage: python3 -I tools/minify_json.py build/project/assets
"""
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
before = after = 0
for p in root.rglob("*.json"):
    raw = p.read_bytes()
    out = json.dumps(json.loads(raw), ensure_ascii=False, separators=(",", ":")).encode()
    assert json.loads(out) == json.loads(raw), p
    p.write_bytes(out)
    before += len(raw)
    after += len(out)
print(f"minify_json: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB")
