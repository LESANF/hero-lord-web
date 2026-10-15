#!/bin/sh
# One command from APK to a static site in build/web/.
#   ./build.sh hero-lord-remaster-20261014-r24.apk [web_nothreads_release.zip]
# The optional second argument skips the template download (see tools/build_web.py).
set -eu
cd "$(dirname "$0")"
APK=$1
TEMPLATE=${2:-}

rm -rf build/project
mkdir -p build/web
python3 -I tools/extract_project.py "$APK" build/project
cp web/override.cfg web/web_shim.gd build/project/
python3 -I tools/pack_pck.py build/project build/web/hero-lord.pck 4.6.0
python3 -I tools/build_web.py build/web $TEMPLATE
