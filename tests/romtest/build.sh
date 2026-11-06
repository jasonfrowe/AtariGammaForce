#!/bin/sh
# Build the 272K cart test: tests/romtest/build.sh -> build/romtest.a78
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BASDIR="$ROOT/tools/7800basic"
WORK="$ROOT/build/romtest"
rm -rf "$WORK"
mkdir -p "$WORK"
python3 "$ROOT/tests/romtest/romtest.py" > /dev/null
cp "$ROOT/tests/romtest/romtest.bas" "$ROOT/tests/romtest/atascii.png" "$WORK/"
cd "$WORK"
bas7800dir="$BASDIR" PATH="$BASDIR:$PATH" sh "$BASDIR/7800basic.sh" romtest.bas > build.log 2>&1 || true
if [ ! -f romtest.bas.a78 ] || grep -q -i -E "error|unresolved|Compilation failed" build.log; then
    grep -i -E -B2 -A2 "error|unresolved|failed" build.log | head -40
    echo "BUILD FAILED (full log: build/romtest/build.log)"
    exit 1
fi
cp romtest.bas.a78 "$ROOT/build/romtest.a78"
echo "built build/romtest.a78 ($(wc -c < romtest.bas.a78 | tr -d ' ') bytes)"
