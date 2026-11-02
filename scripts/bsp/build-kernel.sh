#!/usr/bin/env bash
set -euo pipefail
# Run from the repository root. A Linux volume avoids Windows reserved filenames
# in the upstream kernel (notably nouveau's aux.c).
commit=382f9c6ddcb4a8d4f0162228305545e647cca97c
if [[ ${1:-} != --inside ]]; then
    root=$(cd "$(dirname "$0")/../.." && pwd)
    docker build -f "$root/docker/Dockerfile.kernel" -t r36llm-kernel-builder "$root"
    docker run --rm --mount "type=bind,source=$root,target=/repo" \
        --mount type=volume,source=r36llm-kernel-work,target=/work \
        -e JOBS="${JOBS:-4}" r36llm-kernel-builder \
        bash /repo/scripts/bsp/build-kernel.sh --inside
    exit
fi
src=/work/source
build=/work/build
art=/repo/out/bsp/artifacts
meta=$art/kernel
mkdir -p "$src" "$build" "$meta" /repo/out/bsp/logs
exec > >(tee /repo/out/bsp/logs/kernel-build.log) 2>&1
trap 'echo "Kernel build failed at line $LINENO" >&2' ERR
gitdir=/repo/out/bsp/src/arkos.bsp.4.4/.git
if [[ ! -d "$gitdir" ]]; then
    git init "$(dirname "$gitdir")"
    git --git-dir="$gitdir" fetch --depth=1 https://github.com/lcdyk0517/arkos.bsp.4.4.git "$commit"
    git --git-dir="$gitdir" update-ref HEAD "$commit"
fi
[[ $(git --git-dir="$gitdir" rev-parse HEAD) == "$commit" ]]
if [[ ! -f /work/source-commit || $(cat /work/source-commit) != "$commit" ]]; then
    git --git-dir="$gitdir" archive "$commit" | tar -x -C "$src"
    printf '%s\n' "$commit" > /work/source-commit
fi
exfat_commit=68072a2dc3bf9d73e8bda9b82fa3f93a7e9ff0a5
if [[ ! -d /work/exfat.git ]]; then
    git clone --bare https://github.com/christianhaitian/exfat-linux.git /work/exfat.git
fi
mkdir -p "$src/fs/exfat"
git --git-dir=/work/exfat.git archive "$exfat_commit" | tar -x -C "$src/fs/exfat"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
# esp8089's in-tree makefile also needs the out-of-tree configuration path.
export KBUILD="$build"
export KBUILD_BUILD_TIMESTAMP='2026-11-02 00:00:00 UTC'
export KBUILD_BUILD_USER=r36llm KBUILD_BUILD_HOST=source-build KBUILD_BUILD_VERSION=1
make -C "$src" O="$build" clone_defconfig
cp "$build/.config" "$meta/clone-base.config"
"$src/scripts/kconfig/merge_config.sh" -m -O "$build" "$build/.config" \
    /repo/br2-external/board/r36llm/kernel.fragment
make -C "$src" O="$build" olddefconfig
cp "$build/.config" "$meta/.config"
python3 "$src/scripts/diffconfig" "$meta/clone-base.config" "$build/.config" > "$meta/config.diff"
make -C "$src" O="$build" -j"${JOBS:-4}" Image modules dtbs
# Reconstruct Panel 8 from the licensed BSP and observed hardware data, not
# by redistributing or blindly decompiling the vendor's entire binary tree.
gcc -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
    -I "$src/include" -I "$src/arch/arm64/boot/dts/rockchip" \
    /repo/br2-external/board/r36llm/rk3326-g80ca-panel8.dts \
    -o "$meta/rk3326-g80ca-panel8.preprocessed.dts"
dtc -@ -I dts -O dtb -o "$art/rk3326-r36s-linux.dtb" \
    "$meta/rk3326-g80ca-panel8.preprocessed.dts"
dtc -s -I dtb -O dts -o "$meta/rk3326-g80ca-panel8.decompiled.dts" \
    "$art/rk3326-r36s-linux.dtb"
cp /repo/br2-external/board/r36llm/rk3326-g80ca-panel8.dts "$meta/"
# Drop obsolete modules from earlier configurations of the same kernel release.
mkdir -p "$art/modules"
rm -rf "$art/modules/lib"
rm -f "$art/modules/SHA256SUMS"
make -C "$src" O="$build" INSTALL_MOD_PATH="$art/modules" modules_install
release=$(make -s -C "$src" O="$build" kernelrelease)
depmod -b "$art/modules" "$release"
# Host-specific build/source links are not part of the target module tree.
rm -f "$art/modules/lib/modules/$release/build" "$art/modules/lib/modules/$release/source"
cp "$build/arch/arm64/boot/Image" "$art/Image"
cp -r "$build/arch/arm64/boot/dts/rockchip" "$meta/dtbs"
cp "$src/COPYING" "$meta/COPYING"
cp "$build/System.map" "$meta/System.map"
cp /repo/br2-external/board/r36llm/kernel.fragment "$meta/kernel.fragment"
cp /repo/scripts/bsp/build-kernel.sh "$meta/build-kernel.sh"
cp /repo/docker/Dockerfile.kernel "$meta/Dockerfile.kernel"
{
    printf 'Source: https://github.com/lcdyk0517/arkos.bsp.4.4\nCommit: %s\nDefconfig: clone_defconfig\n' "$commit"
    printf 'exfat source: https://github.com/christianhaitian/exfat-linux\nexfat commit: %s\n' "$exfat_commit"
    printf 'Kernel release: %s\n' "$release"
    aarch64-linux-gnu-gcc --version
    dpkg-query -W gcc-8-aarch64-linux-gnu binutils-aarch64-linux-gnu gcc make device-tree-compiler
} > "$meta/source-info.txt"
git --git-dir="$gitdir" archive --format=tar --prefix=linux-4.4.189/ "$commit" | gzip -n > "$meta/linux-source.tar.gz"
git --git-dir=/work/exfat.git archive --format=tar --prefix=exfat-linux/ "$exfat_commit" | gzip -n > "$meta/exfat-source.tar.gz"
sha256sum "$art/Image" "$art/rk3326-r36s-linux.dtb" "$meta/.config" \
    "$meta/linux-source.tar.gz" "$meta/exfat-source.tar.gz" > "$meta/SHA256SUMS"
