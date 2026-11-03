#!/bin/sh
# Run in a native Linux environment with the repository mounted at /work.
# The caller prepares out/vocab/source with the output-head patch applied.
# Usage: sh scripts/vocab/run-x86.sh [MODEL [KEEP_LIST [CORPUS [REPORT]]]]
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/out/vocab/source"
BUILD="$ROOT/out/vocab/build"
MODEL=${1:-"$ROOT/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf"}
KEEP=${2:-"$ROOT/card/r36llm/output-keep-en-fr.txt"}
CORPUS=${3:-"$ROOT/scripts/vocab/corpus.txt"}
REPORT=${4:-"$ROOT/out/vocab/compare-x86.json"}
if [ "$#" -gt 4 ]; then
    echo "usage: $0 [MODEL [KEEP_LIST [CORPUS [REPORT]]]]" >&2
    exit 2
fi
# An absolute keep path is passed to the engine at model load.
KEEP_DIR=$(CDPATH= cd -- "$(dirname -- "$KEEP")" && pwd)
KEEP="$KEEP_DIR/$(basename -- "$KEEP")"
cmake -S "$SOURCE" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON -DGGML_NATIVE=ON -DGGML_BACKEND_DL=OFF \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_OPENSSL=OFF \
    -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_FATAL_WARNINGS=OFF
cmake --build "$BUILD" --target llama --parallel "${BUILD_JOBS:-4}"
${CXX:-c++} -std=c++17 -O2 -I"$SOURCE/include" -I"$SOURCE/ggml/include" \
    "$ROOT/scripts/vocab/compare.cpp" -L"$BUILD/bin" \
    -Wl,-rpath,"$BUILD/bin" -lllama -lggml -lggml-base -lggml-cpu \
    -o "$BUILD/bin/vocab-compare"
"$BUILD/bin/vocab-compare" "$MODEL" "$KEEP" "$CORPUS" > "$REPORT"
printf 'Report: %s\n' "$REPORT" >&2
