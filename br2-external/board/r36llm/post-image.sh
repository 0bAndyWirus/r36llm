#!/bin/sh
set -eu
BINARIES_DIR=${1:?Usage: post-image.sh BINARIES_DIR}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
DTB="$REPO/vendor/boot-orig/rk3326-r36s-linux.dtb"
[ -f "$DTB" ] || { echo "r36llm: missing vendor DTB: $DTB; see README \"2. Harvest the vendor files\"" >&2; exit 1; }
mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd -d "$BINARIES_DIR/rootfs.cpio.gz" "$BINARIES_DIR/uInitrd"
SIZE=$(wc -c < "$BINARIES_DIR/uInitrd")
if [ "$SIZE" -ge 14680064 ]; then
    echo "r36llm: uInitrd is $SIZE bytes; it must stay below 14 MiB (0x01f00000 - 0x01100000 in boot.ini)" >&2
    exit 1
fi
GADGET_DTB="$BINARIES_DIR/rk3326-r36s-linux-gadget.dtb"
cp "$DTB" "$GADGET_DTB"
fdtput -t s "$GADGET_DTB" /syscon@ff2c0000/usb2-phy@100/otg-port status okay
fdtput -t s "$GADGET_DTB" /usb@ff300000 dr_mode peripheral
fdtput -d "$GADGET_DTB" /usb@ff300000 g-use-dma
mkdir -p "$REPO/out"
cp "$BINARIES_DIR/uInitrd" "$GADGET_DTB" "$BINARIES_DIR/../target/usr/bin/r36llm" "$REPO/out/"
# U-Boot splash and charging screens (replace the stock OS branding on the BOOT partition).
python3 "$REPO/tools/make_boot_images.py" "$REPO/out/boot"
