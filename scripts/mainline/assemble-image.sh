#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
exec > >(tee "$root/out/mainline/logs/image-build.log") 2>&1
boot=$root/out/mainline/boot
rm -rf "$boot"
mkdir -p "$boot/dtbs" "$boot/overlays" "$meta/image"
cp "$art/Image" "$art/uInitrd" "$art/boot.scr" "$boot/"
cp "$art/rk3326-gameconsole-eeclone.dtb" "$boot/dtbs/"
cp "$art/mipi-panel.dtbo" "$boot/overlays/"
if [[ ${R36LLM_USB_HOST:-0} == 1 ]]; then
    cp "$art/usb-host-experimental.dtbo" "$boot/overlays/"
fi
printf 'fresh\n' > "$boot/r36-grow.txt"
python3 - "$boot" "$art/clone_uboot.bin.ddr333" <<'PY'
import pathlib, sys
b = pathlib.Path(sys.argv[1])
for name, address, limit in (
    ('dtbs/rk3326-gameconsole-eeclone.dtb', 0x02000000, 0x08000000 - 0x40000),
    ('overlays/mipi-panel.dtbo', 0x08000000, 0x09000000),
    ('Image', 0x09000000, 0x20000000),
    ('uInitrd', 0x20000000, 0x38000000),
):
    size = (b / name).stat().st_size
    assert address + size < limit, 'Load-address overlap: ' + name
    print('%s: %d bytes at 0x%08x; file ranges do not overlap' % (name, size, address))
assert pathlib.Path(sys.argv[2]).stat().st_size <= 16 * 1024**2 - 32768
print('PASS loader fits before p1; U-Boot relocation/LMB layout still requires a hardware boot')
PY
find "$boot" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
rm -f "$work/boot.vfat" "$work/data.vfat" "$work/swap.img" "$work/readback.bin"
truncate -s 128M "$work/boot.vfat"
mkfs.fat --invariant -F 32 -i 52333653 -n R36BOOT "$work/boot.vfat"
mcopy -s -i "$work/boot.vfat" "$boot/"* ::/
mkdir -p "$work/mainline-data"
printf 'Empty release data partition; initialized on first boot.\n' > "$work/mainline-data/r36-grow.txt"
touch -d "@$SOURCE_DATE_EPOCH" "$work/mainline-data/r36-grow.txt"
truncate -s 128M "$work/data.vfat"
mkfs.fat --invariant -F 32 -i 52333644 -n R36DATA "$work/data.vfat"
mcopy -i "$work/data.vfat" "$work/mainline-data/r36-grow.txt" ::/
truncate -s 512M "$work/swap.img"
mkswap -L R36SWAP -U 52333653-0000-4000-8000-000000000002 "$work/swap.img"
image=$art/r36llm-mainline.img
rm -f "$image"
truncate -s 800M "$image"
sfdisk "$image" <<'TABLE'
label: dos
label-id: 0x52333653
unit: sectors

start=32768, size=262144, type=c, bootable
start=294912, size=1048576, type=82
start=1343488, size=262144, type=c
TABLE
dd if="$art/clone_uboot.bin.ddr333" of="$image" bs=512 seek=64 conv=notrunc status=none
dd if="$work/boot.vfat" of="$image" bs=1M seek=16 conv=notrunc status=none
dd if="$work/swap.img" of="$image" bs=1M seek=144 conv=notrunc status=none
dd if="$work/data.vfat" of="$image" bs=1M seek=656 conv=notrunc status=none
sfdisk --verify "$image" | tee "$meta/image/partition-check.txt"
sfdisk --dump "$image" > "$meta/image/partition-table.txt"
fsck.fat -n "$work/boot.vfat" | tee "$meta/image/boot-fat-check.txt"
mdir -s -i "$work/boot.vfat" ::/ | tee "$meta/image/boot-contents.txt"
# Read back from the assembled image, not only the source FAT directory.
files=(Image uInitrd boot.scr r36-grow.txt dtbs/rk3326-gameconsole-eeclone.dtb overlays/mipi-panel.dtbo)
if [[ ${R36LLM_USB_HOST:-0} == 1 ]]; then
    files+=(overlays/usb-host-experimental.dtbo)
fi
for file in "${files[@]}"; do
    mcopy -i "$image@@16777216" "::/$file" "$work/readback.bin"
    cmp "$boot/$file" "$work/readback.bin"
    rm "$work/readback.bin"
done
python3 - "$image" "$art/clone_uboot.bin.ddr333" <<'PY'
import pathlib, struct, sys
loader = pathlib.Path(sys.argv[2]).read_bytes()
with open(sys.argv[1], 'rb') as f:
    header = f.read(512)
    assert header[510:] == b'\x55\xaa'
    assert struct.unpack_from('<I', header, 440)[0] == 0x52333653
    f.seek(32768)
    assert f.read(len(loader)) == loader
print('PASS MBR signature, disk identifier and raw loader readback at sector 64')
PY
hash_files=(Image uInitrd boot.scr rk3326-gameconsole-eeclone.dtb mipi-panel.dtbo clone_uboot.bin.ddr333 modules.tar.gz r36llm-mainline.img)
if [[ ${R36LLM_USB_HOST:-0} == 1 ]]; then
    hash_files+=(usb-host-experimental.dtbo)
fi
(cd "$art" && sha256sum "${hash_files[@]}" > SHA256SUMS)
printf 'PASS offline mainline image assembly; NO hardware boot performed\n'
