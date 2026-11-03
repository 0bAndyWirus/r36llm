#!/usr/bin/env bash
set -euo pipefail

# Run inside docker/Dockerfile.uboot with this repository mounted at /src.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
case "${R36LLM_UBOOT:-vendor5606e80}" in
    vendor5606e80) exec bash "$root/scripts/bsp/build-vendor-uboot.sh" ;;
    clone4820a71) ;;
    *) echo "R36LLM_UBOOT must be clone4820a71 or vendor5606e80" >&2; exit 1 ;;
esac
artifacts=${R36LLM_UBOOT_ARTIFACTS:-"$root/out/bsp/artifacts"}
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
# A changes DDR init only; B reproduces the working card's complete rkbin set.
# Both variants still compile this project's U-Boot from the pinned source.
variant=${R36LLM_FIRMWARE_VARIANT:-B}
case "$variant" in
    A|B) ;;
    *) echo "R36LLM_FIRMWARE_VARIANT must be A or B" >&2; exit 1 ;;
esac
rkbin="$root/out/rkbin"
rkbin_commit=a92d5e7df36cd1fac4bab24bc953b145fc0159a1
if [[ ! -d "$rkbin/.git" ]]; then
    git init "$rkbin"
fi
git config --global --add safe.directory "$rkbin"
if ! git -C "$rkbin" cat-file -e "$rkbin_commit^{commit}" 2>/dev/null; then
    git -C "$rkbin" fetch --depth=1 https://github.com/rockchip-linux/rkbin.git "$rkbin_commit"
fi
mkdir -p "$artifacts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$source_dir" archive "$commit" | tar -xf - -C "$work"
cd "$work"
patch -p1 < "$root/scripts/bsp/uboot-efi-order.patch"
firmware=tools/rk_tools/bin/rk33
ddr=rk3326_ddr_333MHz_v1.10.bin
miniloader=rk3326_miniloader_v1.40.bin
bl31=rk3326_bl31_v1.34.elf
bl32=rk3326_bl32_v2.19.bin
if [[ "$variant" == B ]]; then
    miniloader=rk3326_miniloader_v1.12.bin
    bl31=rk3326_bl31_v1.14.elf
    bl32=rk3326_bl32_v1.10.bin
fi
git -C "$rkbin" show "$rkbin_commit:bin/rk33/$ddr" > "$firmware/$ddr"
if [[ "$variant" == B ]]; then
    for file in "$miniloader" "$bl31" "$bl32"; do
        git -C "$rkbin" show "$rkbin_commit:bin/rk33/$file" > "$firmware/$file"
    done
fi
# make.sh hardcodes the SD idbloader separately from the RKBOOT manifest.
sed -i \
    -e "s/rk3326_ddr_333MHz_v2.12.bin/$ddr/g" \
    -e "s/rk3326_miniloader_v1.40.bin/$miniloader/g" \
    make.sh tools/rk_tools/RKBOOT/RK3326MINIALL.ini
sed -i \
    -e "s/rk3326_bl31_v1.34.elf/$bl31/g" \
    -e "s/rk3326_bl32_v2.19.bin/$bl32/g" \
    tools/rk_tools/RKTRUST/RK3326TRUST.ini
(
    cd "$firmware"
    # Verify the selected firmware against the recorded upstream hashes.
    for file in "$ddr" "$miniloader" "$bl31" "$bl32"; do
        grep "  $file$" "$root/THIRD-PARTY/firmware/NOTICE"
    done | sha256sum -c -
) > "$metadata/firmware-hashes.txt"
export SOURCE_DATE_EPOCH=$(git -C "$source_dir" show -s --format=%ct "$commit")
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH")"
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=r36s MAKEFLAGS=-l4
./make.sh odroidgoa
dtc -q -I dts -O dtb -o "$artifacts/rg351v-uboot.dtb" "$root/scripts/bsp/rg351v-uboot.dts"
cp sd_fuse/idbloader.img sd_fuse/uboot.img sd_fuse/trust.img "$artifacts/"
cp u-boot.bin "$artifacts/u-boot.bin"
cp "$root/THIRD-PARTY/firmware/NOTICE" "$artifacts/firmware-NOTICE.txt"
cp "$root/THIRD-PARTY/firmware/LICENSE" "$artifacts/firmware-LICENSE.txt"
sha256sum "$artifacts"/{idbloader.img,uboot.img,trust.img,u-boot.bin,rg351v-uboot.dtb}
cp .config "$metadata/.config"
cp "$root/scripts/bsp/build-uboot.sh" "$root/docker/Dockerfile.uboot" "$metadata/"
cp "$root/scripts/bsp/"{uboot-efi-order.patch,rg351v-uboot.dts} "$metadata/"
cp -r Licenses "$metadata/"
git -C "$source_dir" archive --format=tar --prefix=u-boot/ "$commit" | gzip -n > "$metadata/u-boot-source.tar.gz"
{
    printf 'Source: https://github.com/lcdyk0517/Clone-u-boot\nCommit: %s\nDefconfig: odroidgoa\n' "$commit"
    printf 'Firmware variant: %s\nrkbin source: https://github.com/rockchip-linux/rkbin\nrkbin historical commit: %s\n' "$variant" "$rkbin_commit"
    printf 'DDR: %s\nMiniloader: %s\nBL31: %s\nBL32: %s\n' "$ddr" "$miniloader" "$bl31" "$bl32"
    aarch64-linux-gnu-gcc --version
    dpkg-query -W gcc-8-aarch64-linux-gnu binutils-aarch64-linux-gnu gcc make device-tree-compiler
} > "$metadata/source-info.txt"
sha256sum "$artifacts"/{idbloader.img,uboot.img,trust.img,u-boot.bin,rg351v-uboot.dtb} "$metadata/.config" "$metadata/u-boot-source.tar.gz" > "$metadata/SHA256SUMS"
