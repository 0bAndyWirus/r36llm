#!/bin/sh
# Run in r36llm-builder with repo at /src and Buildroot /home/br/work mounted.
# This only stages an isolated prefix; it never installs into the app's lib/.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/out/vocab/source"
BUILD="$ROOT/out/vocab/build-device-make"
PREFIX="$ROOT/out/vocab/prefix-device"
HOST=${BR_HOST:-/home/br/work/output/host}
export PATH="$HOST/bin:$PATH"
"$HOST/bin/cmake" -S "$SOURCE" -B "$BUILD" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$HOST/share/buildroot/toolchainfile.cmake" \
    -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
    -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a -DGGML_OPENMP=ON \
    -DGGML_BACKEND_DL=OFF -DGGML_CPU_ALL_VARIANTS=OFF -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_TOOLS=ON -DLLAMA_BUILD_APP=OFF -DLLAMA_OPENSSL=OFF \
    -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_FATAL_WARNINGS=OFF
"$HOST/bin/cmake" --build "$BUILD" --target llama-bench -j "${BUILD_JOBS:-2}"
mkdir -p "$PREFIX/bin" "$PREFIX/lib"
cp -a "$BUILD/bin/llama-bench" "$PREFIX/bin/"
cp -a "$BUILD/bin/"*.so* "$PREFIX/lib/"
for elf in "$PREFIX/bin/llama-bench" "$PREFIX"/lib/*.so*; do
    if [ ! -L "$elf" ]; then "$HOST/bin/patchelf" --remove-rpath "$elf"; fi
done
# Device data partition is FAT; expand library symlinks inside the tar.
tar --hard-dereference -chf "$ROOT/out/vocab/device-prefix.tar" -C "$PREFIX" bin lib
sha256sum "$ROOT/out/vocab/device-prefix.tar"
