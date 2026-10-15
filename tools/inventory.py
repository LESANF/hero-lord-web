#!/usr/bin/env python3
"""Print what is inside a Godot Android APK without extracting it.

usage: python3 -I tools/inventory.py path/to/game.apk
"""
import collections
import hashlib
import pathlib
import re
import sys
import zipfile


def main(apk_path: str) -> None:
    h = hashlib.sha256()
    with open(apk_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    print("sha256 ", h.hexdigest())

    with zipfile.ZipFile(apk_path) as z:
        infos = [i for i in z.infolist() if not i.is_dir()]
        print("entries", len(infos))

        print("\n# native libs / dex")
        engine_libs = []
        for i in infos:
            if i.filename.startswith("lib/") or i.filename.endswith(".dex"):
                print(f"{i.file_size:>12} {i.filename}")
                if i.filename.endswith("/libgodot_android.so"):
                    engine_libs.append(i.filename)

        print("\n# Godot version string inside libgodot_android.so")
        for name in engine_libs[:1]:
            for m in sorted(set(re.findall(rb"Godot Engine v[0-9A-Za-z.\-_]+", z.read(name)))):
                print(f"  {name}: {m.decode()}")
        if not engine_libs:
            print("  (no libgodot_android.so in this APK: split/config APK?)")

    print("\n# assets/ by extension (Godot project files are stored loose here)")
    assets = [i for i in infos if i.filename.startswith("assets/")]
    ext, size = collections.Counter(), collections.Counter()
    for i in assets:
        e = pathlib.PurePosixPath(i.filename).suffix or "(none)"
        ext[e] += 1
        size[e] += i.file_size
    for e, n in ext.most_common():
        print(f"{n:>7} files {size[e] / 1e6:>8.1f} MB  {e}")

    print("\n# assets/ top-level")
    top = collections.Counter(i.filename.split("/")[1] for i in assets)
    for name, n in top.most_common():
        print(f"{n:>7}  {name}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
