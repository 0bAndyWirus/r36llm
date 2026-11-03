#!/bin/sh
# Extract the pinned engine and apply the package patches in lexical order.
# Usage: sh scripts/vocab/prepare-source.sh [LOCAL_PRISM_GIT [DESTINATION]]
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UPSTREAM=${1:-"$ROOT/out/neon/llama.cpp"}
SOURCE=${2:-"$ROOT/out/vocab/source"}
PIN=5628c7338963b00a598f2a588fd09a79af6d70db
if [ -e "$SOURCE" ]; then
    echo "Refusing to overwrite existing source: $SOURCE" >&2
    exit 1
fi
mkdir -p "$SOURCE"
git -C "$UPSTREAM" archive "$PIN" | tar -x -C "$SOURCE"
for patchfile in "$ROOT"/br2-external/package/prism-llama-cpp/000*.patch; do
    patch --batch -d "$SOURCE" -p1 -i "$patchfile"
done
printf 'Prepared %s at pin %s\n' "$SOURCE" "$PIN"
