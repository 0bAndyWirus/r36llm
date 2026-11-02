#!/bin/sh
set -eu
P=/src/out/profile
HOST=/home/br/work/output/host
export PATH="$HOST/bin:$PATH"
PIN=5628c7338963b00a598f2a588fd09a79af6d70db
mkdir -p "$P/source" "$P/build" "$P/prefix/bin" "$P/prefix/lib"
git -C /src/out/neon/llama.cpp archive "$PIN" | tar -x -C "$P/source"
patch --batch -d "$P/source" -p1 -i /src/br2-external/package/prism-llama-cpp/0001-arm-neon-armv8.0-bonsai-dot.patch
"$HOST/bin/cmake" -S "$P/source" -B "$P/build" -G Ninja \
 -DCMAKE_TOOLCHAIN_FILE="$HOST/share/buildroot/toolchainfile.cmake" \
 -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
 -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a -DGGML_OPENMP=ON \
 -DGGML_BACKEND_DL=OFF -DGGML_CPU_ALL_VARIANTS=OFF -DBUILD_SHARED_LIBS=ON \
 -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
 -DLLAMA_BUILD_TOOLS=ON -DLLAMA_BUILD_APP=OFF -DLLAMA_OPENSSL=OFF \
 -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_FATAL_WARNINGS=OFF
"$HOST/bin/cmake" --build "$P/build" --target llama-bench -j 2
"$HOST/bin/aarch64-buildroot-linux-gnu-g++" -O2 -g0 -std=c++17 -march=armv8-a \
 -I"$P/source/include" -I"$P/source/ggml/include" "$P/profile.cpp" \
 -L"$P/build/bin" -Wl,-rpath-link,"$P/build/bin" -lllama -lggml -lggml-base -lggml-cpu \
 -o "$P/prefix/bin/profile"
cp -a "$P/build/bin/llama-bench" "$P/prefix/bin/"
cp -a "$P/build/bin/"*.so* "$P/prefix/lib/"
for elf in "$P/prefix/bin/"* "$P/prefix/lib/"*.so*; do
 if [ ! -L "$elf" ]; then "$HOST/bin/patchelf" --remove-rpath "$elf"; fi
done
cd "$P/prefix"
# /data is FAT: expand both symbolic and hard links; device tar lacks gzip.
tar --hard-dereference -chf "$P/profile.tar" bin lib
sha256sum "$P/profile.tar" "$P/prefix/bin/profile" "$P/prefix/bin/llama-bench"
