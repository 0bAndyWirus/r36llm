#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
exec > >(tee "$root/out/mainline/logs/initramfs-build.log") 2>&1
input=${1:-/repo/out/uInitrd}
[[ -s $input ]] || { echo "Build the existing Buildroot initramfs first: scripts/build.ps1 -Release" >&2; exit 1; }
ramroot=$work/initramfs
rm -rf "$ramroot"
mkdir -p "$ramroot" "$meta/initramfs"
# Verify both legacy header and payload CRC before passing it to host tools.
python3 - "$input" <<'PY'
import pathlib, struct, sys, zlib
p = pathlib.Path(sys.argv[1]).read_bytes()
h = bytearray(p[:64])
magic, header_crc, timestamp, size, load, entry, data_crc = struct.unpack('>7I', h[:28])
assert magic == 0x27051956 and len(p) == 64 + size
h[4:8] = b'\0' * 4
assert zlib.crc32(h) == header_crc and zlib.crc32(p[64:]) == data_crc
assert p[28:31] == bytes((5, 22, 3)) and p[31] in (0, 1), 'Expected Linux ARM64 legacy ramdisk'
assert p[64:66] == b'\x1f\x8b', 'Expected gzip cpio payload'
print('PASS input uInitrd header CRC, payload CRC, type and length')
PY
dumpimage -T ramdisk -p 0 -o "$work/rootfs.cpio.gz" "$input"
(cd "$ramroot" && gzip -dc "$work/rootfs.cpio.gz" | cpio -idm --quiet --no-absolute-filenames)
[[ -e $ramroot/init ]]
python3 - "$work/modules" "$ramroot" <<'PY'
import pathlib, shutil, sys
source_root, target = map(pathlib.Path, sys.argv[1:])
roots = list((source_root / 'lib/modules').iterdir())
assert len(roots) == 1
source = roots[0]
deps = dict((line.split(':', 1)[0], line.split(':', 1)[1].split()) for line in (source / 'modules.dep').read_text().splitlines())
builtins = {pathlib.PurePosixPath(p).stem.replace('-', '_') for p in (source / 'modules.builtin').read_text().splitlines()}
module_root = target / 'lib/modules'
shutil.rmtree(module_root, ignore_errors=True)
(module_root / source.name).mkdir(parents=True)
for file in ('modules.builtin', 'modules.builtin.modinfo', 'modules.order'):
    if (source / file).exists():
        shutil.copyfile(source / file, module_root / source.name / file)
def collect(names):
    order, seen = [], set()
    def visit(p):
        rel = pathlib.PurePosixPath(p)
        assert not rel.is_absolute() and '..' not in rel.parts
        if p in seen:
            return
        seen.add(p)
        for dep in deps[p]:
            visit(dep)
        order.append(p)
    for name in names:
        matches = [p for p in deps if pathlib.PurePosixPath(p).name == name + '.ko']
        if len(matches) == 1:
            visit(matches[0])
        elif name.replace('-', '_') not in builtins:
            raise ValueError('Required driver absent: ' + name)
    for p in order:
        dest = module_root / source.name / p
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / p, dest)
    return ''.join('/lib/modules/%s/%s\n' % (source.name, p) for p in order)
config = target / 'etc/r36llm'
for file, names in (
    ('net-modules.txt', ('dwc2', 'ax88179_178a', 'r8152', 'asix', 'cdc_ether', 'cdc_ncm', 'smsc95xx')),
    ('gadget-modules.txt', ('dwc2', 'usb_f_ncm', 'usb_f_rndis')),
    ('exfat-module.txt', ('exfat',)),
    ('joypad-modules.txt', ('archr-singleadc-joypad',)),
):
    (config / file).write_text(collect(names))
inittab = target / 'etc/inittab'
inittab.write_text(inittab.read_text().replace('ttyFIQ0', 'ttyS2'))
defaults = config / 'defaults/config.ini'
text = defaults.read_text()
import re
text, count = re.subn(r'^keymap=.*$', 'keymap=mainline', text, flags=re.M)
assert count <= 1
if count == 0:
    text = text.rstrip() + '\nkeymap=mainline\n'
defaults.write_text(text)
assert not any(p.name.startswith('4.4.') for p in module_root.iterdir())
print('PASS mainline module closure, serial getty and default keymap')
PY
cat > "$ramroot/etc/init.d/S04joypad" <<'SH'
#!/bin/sh
case "${1:-start}" in
    start)
        while IFS= read -r module; do
            [ -z "$module" ] || insmod "$module" || exit 1
        done < /etc/r36llm/joypad-modules.txt
        ;;
esac
SH
chmod 0755 "$ramroot/etc/init.d/S04joypad"
release=$(cat "$meta/kernel/kernelrelease")
depmod -b "$ramroot" "$release"
# Sorting and fixed mtimes avoid directory traversal order and wall-clock differences.
find "$ramroot" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(cd "$ramroot" && find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --reproducible --owner=0:0 --quiet | gzip -n > "$work/mainline-rootfs.cpio.gz")
mkimage -A arm64 -O linux -T ramdisk -C gzip -a 0 -e 0 -n r36llm-mainline-initramfs \
    -d "$work/mainline-rootfs.cpio.gz" "$art/uInitrd"
mkimage -l "$art/uInitrd" | tee "$meta/initramfs/mkimage.txt"
(cd "$ramroot" && find . -type f | sort) > "$meta/initramfs/contents.txt"
sha256sum "$input" "$art/uInitrd" > "$meta/initramfs/SHA256SUMS"
printf 'PASS initramfs staged for %s, joypad loaded before application startup\n' "$release"
