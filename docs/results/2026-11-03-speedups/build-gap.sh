#!/bin/sh
# Apply app-gap.patch to an isolated repository copy, then:
# CXX=/path/to/Buildroot/bin/aarch64-buildroot-linux-gnu-g++ \
#   sh build-gap.sh ENGINE_SOURCE ENGINE_PREFIX APP_SOURCE OUTPUT_BINARY
set -eu
if [ "$#" -ne 4 ]; then
    echo "usage: $0 ENGINE_SOURCE ENGINE_PREFIX APP_SOURCE OUTPUT_BINARY" >&2
    exit 2
fi
SOURCE=$1
PREFIX=$2
APP_SOURCE=$3
OUTPUT=$4
CXX=${CXX:-aarch64-linux-gnu-g++}
"$CXX" -O2 -g0 -std=c++17 -march=armv8-a -pthread \
    -DR36LLM_ENGINE_VERSION='"gap-diagnostic"' \
    -I"$SOURCE/include" -I"$SOURCE/ggml/include" "$APP_SOURCE"/src/*.cpp \
    -L"$PREFIX/lib" -Wl,-rpath-link,"$PREFIX/lib" \
    -lllama -lggml -lggml-base -lggml-cpu -o "$OUTPUT"
sha256sum "$OUTPUT"
