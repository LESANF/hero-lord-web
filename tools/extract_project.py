#!/usr/bin/env python3
"""Extract the exported Godot project that a Godot Android APK carries loose under assets/.

usage: python3 -I tools/extract_project.py game.apk build/project
"""
import pathlib
import sys
import zipfile

# Android-only leftovers that the web build must not carry.
SKIP = ("assets/_cl_", "assets/dexopt/", "assets/assets.sparsepck")


def main(apk: str, out: str) -> None:
    root = pathlib.Path(out).resolve()
    n = 0
    with zipfile.ZipFile(apk) as z:
        for i in z.infolist():
            if i.is_dir() or not i.filename.startswith("assets/") or i.filename.startswith(SKIP):
                continue
            rel = pathlib.PurePosixPath(i.filename[len("assets/"):])
            if ".." in rel.parts or rel.is_absolute():
                raise SystemExit(f"refusing suspicious path in APK: {i.filename}")
            dest = root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(z.read(i))
            n += 1
    print(f"{n} files -> {root}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
