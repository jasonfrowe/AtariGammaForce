#!/bin/sh
# Build the game with the vendored 7800basic.
#
#   tools/build.sh                          -> build/gammaforce.a78
#   GF_DEFINES="CHEAT BOSSTEST" tools/build.sh -> build/gammaforce-test.a78
#     (test builds: each name becomes "const NAME = 1"; see gammaforce.bas)
#
# 7800basic writes its intermediate files next to the source, so the build
# runs in a copy of src/ under build/work and copies the results out.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASDIR="$ROOT/tools/7800basic"
WORK="$ROOT/build/work"

rm -rf "$WORK"
mkdir -p "$WORK"
cp -R "$ROOT/src/." "$WORK/"
# 7800basic turns an inline file's path into a symbol name, so a "/" in
# it breaks the assembly: assembly files go flat into the work directory.
cp "$ROOT"/src/asm/*.asm "$ROOT"/src/gen/*.asm "$WORK/"
OUTNAME=gammaforce
if [ -n "$GF_DEFINES" ]; then
    OUTNAME=gammaforce-test
    for d in $GF_DEFINES; do
        sed -i.bak "s/^  rem const $d = 1/  const $d = 1/" "$WORK/gammaforce.bas"
    done
fi

cd "$WORK"
bas7800dir="$BASDIR" PATH="$BASDIR:$PATH" sh "$BASDIR/7800basic.sh" gammaforce.bas > build.log 2>&1 || true
if [ ! -f gammaforce.bas.a78 ] || grep -q -i -E "error|unresolved|Compilation failed" build.log; then
    grep -i -E -B2 -A2 "error|unresolved|failed" build.log | head -60
    echo "BUILD FAILED (full log: build/work/build.log)"
    exit 1
fi
cp gammaforce.bas.a78 "$ROOT/build/$OUTNAME.a78"
cp gammaforce.bas.bin "$ROOT/build/$OUTNAME.bin"
grep -E "bytes of ROM space left|used as zone memory|bytes left in the 7800basic reserved area" build.log || true
echo "built build/$OUTNAME.a78"
