#!/usr/bin/env bash
# Verifies that the vendored LAME sources in Sources/CLame are byte-identical
# to the official LAME 3.100 release tarball.
#
# Usage: Packages/LameKit/Scripts/verify-lame-sources.sh
# Needs: curl, tar, shasum or sha256sum, diff.
set -euo pipefail

URL="https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz"
EXPECTED_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Lade $URL"
curl -fsSL -o "$WORK_DIR/lame-3.100.tar.gz" "$URL"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256="$(sha256sum "$WORK_DIR/lame-3.100.tar.gz" | awk '{print $1}')"
else
    ACTUAL_SHA256="$(shasum -a 256 "$WORK_DIR/lame-3.100.tar.gz" | awk '{print $1}')"
fi

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "FEHLER: SHA-256 stimmt nicht: $ACTUAL_SHA256" >&2
    exit 1
fi
echo "SHA-256 OK: $ACTUAL_SHA256"

tar -xzf "$WORK_DIR/lame-3.100.tar.gz" -C "$WORK_DIR"
UPSTREAM="$WORK_DIR/lame-3.100"
VENDORED="$PACKAGE_DIR/Sources/CLame"

status=0
while IFS= read -r -d '' file; do
    relative="${file#"$VENDORED"/}"
    case "$relative" in
        config.h) continue ;;                      # project specific, see header comment
        include/lame.h) upstream_file="$UPSTREAM/include/lame.h" ;;
        *) upstream_file="$UPSTREAM/libmp3lame/$relative" ;;
    esac
    if ! diff -q "$file" "$upstream_file" >/dev/null; then
        echo "ABWEICHUNG: $relative" >&2
        status=1
    fi
done < <(find "$VENDORED" -type f \( -name '*.c' -o -name '*.h' \) -print0)

diff -q "$PACKAGE_DIR/COPYING-LAME.txt" "$UPSTREAM/COPYING" >/dev/null || { echo "ABWEICHUNG: COPYING" >&2; status=1; }

if [[ $status -eq 0 ]]; then
    echo "Alle vendorten LAME-Dateien sind identisch mit LAME 3.100."
fi
exit $status
