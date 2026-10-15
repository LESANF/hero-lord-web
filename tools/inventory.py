#!/usr/bin/env python3
"""Print what is inside a Godot Android APK without extracting it.

usage: python3 -I tools/inventory.py path/to/game.apk
"""
import collections
import hashlib
import re
import sys
import zipfile


def main(apk_path: str) -> None:
    with open(apk_path, "rb") as f:
        print("sha256 ", hashlib.sha256(f.read()).hexdigest())
    z = zipfile.ZipFile(apk_path)
    infos = z.infolist()
    print("entries", len(infos))

    print("\n# native libs / dex")
    for i in infos:
        if i.filename.startswith("lib/") or i.filename.endswith(".dex"):
            print(f"{i.file_size:>12} {i.filename}")

    print("\n# Godot version string inside libgodot_android.so (arm64)")
    so = z.read("lib/arm64-v8a/libgodot_android.so")
    for m in sorted(set(re.findall(rb"Godot Engine v[0-9A-Za-z.\-_]+", so))):
        print(" ", m.decode())

    print("\n# assets/ by extension (Godot project files are stored loose here)")
    ext = collections.Counter()
    size = collections.Counter()
    for i in infos:
        if not i.filename.startswith("assets/") or i.is_dir():
            continue
        e = i.filename.rsplit(".", 1)[-1] if "." in i.filename.rsplit("/", 1)[-1] else "(none)"
        ext[e] += 1
        size[e] += i.file_size
    for e, n in ext.most_common():
        print(f"{n:>7} files {size[e] / 1e6:>8.1f} MB  .{e}")

    print("\n# assets/ top-level")
    top = collections.Counter(i.filename.split("/")[1] for i in infos if i.filename.startswith("assets/"))
    for name, n in top.most_common():
        print(f"{n:>7}  {name}")


if __name__ == "__main__":
    main(sys.argv[1])
