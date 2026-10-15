#!/bin/sh
# Re-encode the game's PCM .sample audio to QOA in place (same AudioStreamWAV type, ~5x smaller).
#   tools/compress_audio.sh build/project
# Uses $GODOT if set; otherwise downloads the official Godot 4.6 binary for this
# machine into build/godot/ (sha256 pinned) and runs it headless.
set -eu
cd "$(dirname "$0")/.."
DIR=$1
if [ -z "${GODOT:-}" ]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)
      ZIP=Godot_v4.6-stable_linux.x86_64.zip; BIN=Godot_v4.6-stable_linux.x86_64
      SHA=6bcc59dfd1d670e918c77eae06e82b9dc5699de13d353dc3a4b3b6b307b6dc06 ;;
    Darwin-*)
      ZIP=Godot_v4.6-stable_macos.universal.zip; BIN=Godot.app/Contents/MacOS/Godot
      SHA=fc15ceb6280420f117ab4ef62332654db0088078faeeb9025dd814276185ed3b ;;
    *) echo "compress_audio: no pinned Godot build for $(uname -s)-$(uname -m); set GODOT=/path/to/godot" >&2; exit 1 ;;
  esac
  GODOT="build/godot/$BIN"
  if [ ! -x "$GODOT" ]; then
    mkdir -p build/godot
    curl -fsSL -o "build/godot/$ZIP" "https://github.com/godotengine/godot-builds/releases/download/4.6-stable/$ZIP"
    if command -v sha256sum >/dev/null; then echo "$SHA  build/godot/$ZIP" | sha256sum -c - >/dev/null
    else echo "$SHA  build/godot/$ZIP" | shasum -a 256 -c - >/dev/null; fi
    # python instead of unzip: not every build image ships unzip
    python3 -I -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "build/godot/$ZIP" build/godot
    chmod +x "$GODOT"
  fi
fi
"$GODOT" --headless --script tools/compress_audio.gd -- "$DIR/.godot/imported" 2>&1 | grep -v '^Godot Engine v'
