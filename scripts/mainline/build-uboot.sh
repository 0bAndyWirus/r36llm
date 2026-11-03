#!/usr/bin/env bash
set -euo pipefail

# Shared source checkouts and all build products live on the Linux work volume.
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
fetch_archr
uboot_commit=e50b1e8715011def8aff1588081a2649a2c6cd47
rkbin_commit=74213af1e952c4683d2e35952507133b61394862
fetch_git https://github.com/u-boot/u-boot.git "$uboot_commit" "$work/uboot-git"
fetch_git https://github.com/rockchip-linux/rkbin.git "$rkbin_commit" "$work/rkbin"

pkg="$archr/projects/ArchR/devices/RK3326/packages/u-boot"
helper="$archr/projects/ArchR/bootloader/rkhelper"
build="$work/uboot-build"
metadata="$meta/uboot"
mkdir -p "$art" "$metadata"
rm -f "$art/clone_uboot.bin.ddr333" "$art/boot.scr"
rm -rf "$build" "$metadata/licenses" "$metadata/archr-sources"
mkdir -p "$build" "$metadata/licenses" "$metadata/archr-sources"
git -C "$work/uboot-git" archive "$uboot_commit" | tar -xf - -C "$build"
cp -a "$pkg/sources/." "$build/"
patch_file="$pkg/patches/0001-add-support-for-k36-clone-with-emmc-rk3326.patch"
patch -d "$build" -p1 < "$patch_file"

export ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- DEBUG=0 LDFLAGS=
make -C "$build" rk3326-handheld_defconfig
# The boot.ini requires script bootflow, MMC/FAT loading, DT overlays and
# legacy images for its script and external uInitrd. HUSH_PARSER also builds test.o.
for config in CMD_BOOTI CMD_FDT OF_LIBFDT_OVERLAY LEGACY_IMAGE_FORMAT \
              CMD_MMC CMD_FS_GENERIC FS_FAT BOOTSTD BOOTMETH_SCRIPT \
              CMD_BOOTFLOW CMD_BOOTMETH HUSH_PARSER; do
    if ! grep -Fxq "CONFIG_${config}=y" "$build/.config"; then
        echo "Missing required U-Boot option CONFIG_${config}=y" >&2
        exit 1
    fi
done
grep -Fxq 'CONFIG_BOOTCOMMAND="bootmeth order script; bootflow scan -b"' "$build/.config"
cp "$build/.config" "$metadata/config"
make -C "$build" -j"${JOBS:-$(nproc)}" u-boot-dtb.bin

# Use the unmodified stock DDR333 blob, not Arch R's 666 MHz retune.
# rkhelper writes idbloader, uboot, and trust at its documented offsets.
(
    cd "$build"
    # The downloaded, pinned Arch R helper consumes these exported inputs.
    export DEVICE=RK3326
    export PKG_BUILD="$build"
    export PKG_RKBIN="$work/rkbin"
    export PKG_DDR_BIN="$PKG_RKBIN/bin/rk33/rk3326_ddr_333MHz_v2.11.bin"
    export PKG_MINILOADER="$PKG_RKBIN/bin/rk33/rk3326_miniloader_v1.40.bin"
    export PKG_BL31="$PKG_RKBIN/bin/rk33/rk3326_bl31_v1.34.elf"
    # The helper is downloaded into the Linux build volume, not the repository.
    # shellcheck source=/dev/null
    source "$helper"
)
# The combined loader is written at sector 64; it must not reach p1 at 16 MiB.
(( $(stat -c %s "$build/uboot.bin") <= 16 * 1024 * 1024 - 64 * 512 )) || {
    echo 'Combined U-Boot image overlaps the boot partition' >&2
    exit 1
}
"$build/tools/mkimage" -A arm64 -O linux -T script -C none -n r36llm-mainline \
    -d "$root/br2-external/board/r36llm-mainline/boot.ini" "$build/boot.scr"
"$build/tools/mkimage" -l "$build/boot.scr" | tee "$metadata/boot.scr.list"

cp "$work/rkbin/LICENSE" "$metadata/licenses/rkbin-LICENSE"
cp "$work/rkbin/README" "$metadata/licenses/rkbin-README"
cp -a "$build/Licenses" "$metadata/licenses/u-boot-Licenses"
cp "$build/README" "$metadata/licenses/u-boot-README"
git -C "$work/uboot-git" archive "$uboot_commit" | gzip -n > "$metadata/u-boot-source.tar.gz"
cp -a "$pkg/sources" "$metadata/archr-sources/"
cp "$patch_file" "$helper" "$pkg/package.mk" "$metadata/archr-sources/"
cp "$archr/projects/ArchR/packages/tools/rkbin/package.mk" "$metadata/archr-sources/rkbin-package.mk"
cp "$root/br2-external/board/r36llm-mainline/boot.ini" "$metadata/boot.ini"
cp "$build/trust.ini" "$metadata/trust.ini"
{
    printf 'Arch R https://github.com/archr-linux/Arch-R.git 6b4904f99bef3fffab490b5ea70ac7de15735885\n'
    printf 'U-Boot https://github.com/u-boot/u-boot.git %s (v2025.10)\n' "$uboot_commit"
    printf 'rkbin https://github.com/rockchip-linux/rkbin.git %s\n' "$rkbin_commit"
    printf 'DDR source: unmodified rk3326_ddr_333MHz_v2.11.bin; default UART, BL32 disabled\n'
    aarch64-linux-gnu-gcc --version
} > "$metadata/sources.txt"
(
    cd "$work/rkbin"
    sha256sum bin/rk33/rk3326_ddr_333MHz_v2.11.bin \
        bin/rk33/rk3326_miniloader_v1.40.bin bin/rk33/rk3326_bl31_v1.34.elf \
        tools/loaderimage tools/trust_merger LICENSE
) > "$metadata/rkbin-sha256.txt"
(
    cd "$metadata"
    find archr-sources licenses -type f -print0 | sort -z | xargs -0 sha256sum
    sha256sum boot.ini config trust.ini boot.scr.list sources.txt rkbin-sha256.txt
) > "$metadata/input-sha256.txt"
cp "$build/uboot.bin" "$art/clone_uboot.bin.ddr333"
cp "$build/boot.scr" "$art/boot.scr"
(
    cd "$art"
    sha256sum clone_uboot.bin.ddr333 boot.scr
) > "$metadata/artifact-sha256.txt"
