#!/bin/sh
set -eu
BINARIES_DIR=${1:?Usage: post-image.sh BINARIES_DIR}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BOARD="$REPO/br2-external/board/r36llm"
ARTIFACTS="$REPO/out/bsp/artifacts"
for file in Image rk3326-r36s-linux.dtb idbloader.img uboot.img trust.img; do
    [ -f "$ARTIFACTS/$file" ] || { echo "r36llm: missing source-build artifact $file; run scripts/build.ps1" >&2; exit 1; }
    cp "$ARTIFACTS/$file" "$BINARIES_DIR/$file"
done
mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd -d "$BINARIES_DIR/rootfs.cpio.gz" "$BINARIES_DIR/uInitrd"
SIZE=$(wc -c < "$BINARIES_DIR/uInitrd")
if [ "$SIZE" -ge 14680064 ]; then
    echo "r36llm: uInitrd is $SIZE bytes; must stay below 14 MiB (DTB load address)" >&2
    exit 1
fi
GADGET_DTB="$BINARIES_DIR/rk3326-r36s-linux-gadget.dtb"
cp "$BINARIES_DIR/rk3326-r36s-linux.dtb" "$GADGET_DTB"
fdtput -t s "$GADGET_DTB" /syscon@ff2c0000/usb2-phy@100/otg-port status okay
fdtput -t s "$GADGET_DTB" /usb@ff300000 dr_mode peripheral
fdtput -d "$GADGET_DTB" /usb@ff300000 g-use-dma
mkdir -p "$REPO/out/boot"
python3 "$REPO/tools/make_boot_images.py" "$REPO/out/boot"
cp "$REPO/out/boot/"*.bmp "$BINARIES_DIR/"
cp "$BOARD/boot.ini" "$BINARIES_DIR/boot.ini"
printf 'fresh\n' > "$BINARIES_DIR/grow-boot.txt"
printf 'Empty release data partition; initialized on first boot.\n' > "$BINARIES_DIR/grow-data.txt"
truncate -s 512M "$BINARIES_DIR/swap.img"
mkswap -L R36SWAP "$BINARIES_DIR/swap.img"
truncate -s 16M "$BINARIES_DIR/padding.bin"
TMP="$BINARIES_DIR/genimage.tmp"
rm -rf "$TMP"
mkdir -p "$BINARIES_DIR/genimage-root"
genimage --rootpath "$BINARIES_DIR/genimage-root" --tmppath "$TMP" --inputpath "$BINARIES_DIR" --outputpath "$BINARIES_DIR" --config "$BOARD/genimage.cfg"
cp "$BINARIES_DIR/uInitrd" "$GADGET_DTB" "$BINARIES_DIR/../target/usr/bin/r36llm" "$REPO/out/"
cp "$BINARIES_DIR/r36llm.img" "$ARTIFACTS/r36llm.img"
(cd "$ARTIFACTS" && sha256sum r36llm.img > r36llm.img.sha256)
# Capture all Buildroot package licenses and corresponding source archives.
# Run `scripts/build.ps1 legal-info` before distributing, and ship that output too.
