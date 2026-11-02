#!/usr/bin/env bash
set -euo pipefail

# Run inside docker/Dockerfile.uboot with this repository mounted at /src.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
artifacts="$root/out/bsp/artifacts"
metadata="$artifacts/uboot"
mkdir -p "$metadata" "$root/out/bsp/logs"
exec > >(tee "$root/out/bsp/logs/uboot-build.log") 2>&1
source_dir="$root/out/bsp/src/Clone-u-boot"
commit=4820a715c2977495f5afa4fc92e1ac9c5311f769
if [[ ! -d "$source_dir/.git" ]]; then
    git init "$source_dir"
    git -C "$source_dir" fetch --depth=1 https://github.com/lcdyk0517/Clone-u-boot.git "$commit"
    git -C "$source_dir" update-ref HEAD "$commit"
fi
git config --global --add safe.directory "$source_dir"
actual=$(git -C "$source_dir" rev-parse HEAD)
if [ "$actual" != "$commit" ]; then
    echo "Expected Clone-u-boot $commit, found $actual" >&2
    exit 1
fi
mkdir -p "$root/out/bsp/artifacts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$source_dir" archive "$commit" | tar -xf - -C "$work"
cd "$work"
patch -p1 < "$root/scripts/bsp/uboot-efi-order.patch"
export SOURCE_DATE_EPOCH=$(git -C "$source_dir" show -s --format=%ct "$commit")
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH")"
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=r36s MAKEFLAGS=-l4
./make.sh odroidgoa
cp sd_fuse/idbloader.img sd_fuse/uboot.img sd_fuse/trust.img "$root/out/bsp/artifacts/"
cp u-boot.bin "$root/out/bsp/artifacts/u-boot.bin"
cp "$root/THIRD-PARTY/firmware/NOTICE" "$root/out/bsp/artifacts/firmware-NOTICE.txt"
cp "$root/THIRD-PARTY/firmware/LICENSE" "$root/out/bsp/artifacts/firmware-LICENSE.txt"
sha256sum "$root"/out/bsp/artifacts/{idbloader.img,uboot.img,trust.img,u-boot.bin}
cp .config "$metadata/.config"
cp "$root/scripts/bsp/build-uboot.sh" "$root/docker/Dockerfile.uboot" "$metadata/"
cp "$root/scripts/bsp/uboot-efi-order.patch" "$metadata/"
cp -r Licenses "$metadata/"
git -C "$source_dir" archive --format=tar --prefix=u-boot/ "$commit" | gzip -n > "$metadata/u-boot-source.tar.gz"
{
    printf 'Source: https://github.com/lcdyk0517/Clone-u-boot\nCommit: %s\nDefconfig: odroidgoa\n' "$commit"
    aarch64-linux-gnu-gcc --version
    dpkg-query -W gcc-8-aarch64-linux-gnu binutils-aarch64-linux-gnu gcc make device-tree-compiler
} > "$metadata/source-info.txt"
sha256sum "$artifacts"/{idbloader.img,uboot.img,trust.img,u-boot.bin} "$metadata/.config" "$metadata/u-boot-source.tar.gz" > "$metadata/SHA256SUMS"
