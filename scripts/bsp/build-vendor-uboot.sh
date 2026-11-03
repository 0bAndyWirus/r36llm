#!/usr/bin/env bash
set -euo pipefail

# Reproduce the working card's U-Boot with a build-order-only EFI dependency fix.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
artifacts=${R36LLM_UBOOT_ARTIFACTS:-"$root/out/bsp/artifacts"}
metadata="$artifacts/uboot"
mkdir -p "$metadata" "$root/out/bsp/logs"
exec > >(tee "$root/out/bsp/logs/uboot-vendor-build.log") 2>&1
commit=5606e804ffe8f9e5427d55c8da04c638f01a9391
source_url=https://github.com/lcdyk0517/Clone-u-boot.git
source_dir="$root/out/bsp/src/vendor-5606e80"
# The historical repository may also be supplied as a local mirror.
source_url=${R36LLM_VENDOR_UBOOT_SOURCE:-$source_url}
if [[ ! -d "$source_dir/.git" ]]; then
    git init "$source_dir"
fi
git config --global --add safe.directory "$source_dir"
if ! git -C "$source_dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$source_dir" fetch --depth=1 "$source_url" "$commit"
fi
rkbin="$root/out/rkbin"
rkbin_commit=a92d5e7df36cd1fac4bab24bc953b145fc0159a1
if [[ ! -d "$rkbin/.git" ]]; then
    git init "$rkbin"
fi
git config --global --add safe.directory "$rkbin"
if ! git -C "$rkbin" cat-file -e "$rkbin_commit^{commit}" 2>/dev/null; then
    git -C "$rkbin" fetch --depth=1 https://github.com/rockchip-linux/rkbin.git "$rkbin_commit"
fi
toolchain=${R36LLM_VENDOR_TOOLCHAIN:-/opt/vendor-linaro}
"$toolchain/bin/aarch64-linux-gnu-gcc" --version | grep -F 'Linaro GCC 6.3-2017.05'
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/source" "$work/prebuilts/gcc/linux-x86/aarch64"
ln -s "$toolchain" "$work/prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu"
git -C "$source_dir" archive "$commit" | tar -xf - -C "$work/source"
cd "$work/source"
# Preserve SOURCE_DATE_EPOCH determinism, but use the vendor's +1100 zone.
patch -p1 < "$root/scripts/bsp/uboot-vendor-timestamp.patch"
patch -p1 < "$root/scripts/bsp/uboot-efi-order.patch"
printf '%s\n' '-g5606e80' > .scmversion
firmware=tools/rk_tools/bin/rk33
files=(rk3326_ddr_333MHz_v1.10.bin rk3326_miniloader_v1.12.bin rk3326_bl31_v1.14.elf rk3326_bl32_v1.10.bin)
for file in "${files[@]}"; do
    git -C "$rkbin" show "$rkbin_commit:bin/rk33/$file" > "$firmware/$file"
done
(
    cd "$firmware"
    for file in "${files[@]}"; do
        grep "  $file$" "$root/THIRD-PARTY/firmware/NOTICE"
    done | sha256sum -c -
) > "$metadata/firmware-hashes.txt"
export SOURCE_DATE_EPOCH=1770327932 TZ=UTC-11
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=r36s MAKEFLAGS=-l4
./make.sh odroidgoa
cp sd_fuse/idbloader.img sd_fuse/uboot.img sd_fuse/trust.img u-boot.bin "$artifacts/"
dtc -q -I dts -O dtb -o "$artifacts/rg351v-uboot.dtb" "$root/scripts/bsp/rg351v-uboot.dts"
cp "$root/THIRD-PARTY/firmware/NOTICE" "$artifacts/firmware-NOTICE.txt"
cp "$root/THIRD-PARTY/firmware/LICENSE" "$artifacts/firmware-LICENSE.txt"
cp .config u-boot.map u-boot.sym "$metadata/"
cp "$root/scripts/bsp/"{build-uboot.sh,build-vendor-uboot.sh,uboot-vendor-timestamp.patch,uboot-efi-order.patch,rg351v-uboot.dts} "$root/docker/Dockerfile.uboot" "$metadata/"
cp -r Licenses "$metadata/"
git -C "$source_dir" archive --format=tar --prefix=u-boot/ "$commit" | gzip -n > "$metadata/u-boot-source.tar.gz"
{
    printf 'Source: %s\nCommit: %s\nDefconfig: odroidgoa\nBuild: ./make.sh odroidgoa\n' "$source_url" "$commit"
    printf 'SOURCE_DATE_EPOCH: %s\nTZ: %s\nVersion suffix: -g5606e80\n' "$SOURCE_DATE_EPOCH" "$TZ"
    printf 'rkbin: https://github.com/rockchip-linux/rkbin\nCommit: %s\n' "$rkbin_commit"
    printf 'Display DTB: GPL-2.0+ vendor DTB decompilation; see rg351v-uboot.dts provenance\n'
    "$toolchain/bin/aarch64-linux-gnu-gcc" --version
    "$toolchain/bin/aarch64-linux-gnu-ld" --version
    dtc --version
} > "$metadata/source-info.txt"
sha256sum "$artifacts"/{idbloader.img,uboot.img,trust.img,u-boot.bin,rg351v-uboot.dtb} "$metadata/.config" "$metadata/u-boot-source.tar.gz" > "$metadata/SHA256SUMS"
cat "$metadata/SHA256SUMS"
