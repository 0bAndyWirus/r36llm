#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
exec > >(tee "$root/out/mainline/logs/kernel-build.log") 2>&1
fetch_archr
src=$work/linux-6.12.114
build=$work/kernel-build
km=$meta/kernel
mkdir -p "$km" "$work/downloads" "$build"
archive=$work/downloads/linux-6.12.114.tar.xz
if [[ ! -f $archive ]]; then
    curl -fL --retry 3 https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.12.114.tar.xz -o "$archive.tmp"
    mv "$archive.tmp" "$archive"
fi
printf '%s  %s\n' 7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3 "$archive" | sha256sum -c -
# This reproduces scripts/unpack's package, architecture, flavour, version,
# project and device ordering. LINUX is unset in the pinned RK3326 configuration.
python3 - "$archr" "$km/patch-order.txt" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
pkg = root / 'projects/ArchR/packages/linux/patches'
prj = root / 'projects/ArchR/patches/linux'
dev = root / 'projects/ArchR/devices/RK3326/patches/linux'
layers = ('mainline', 'RK3326', 'default', 'mainline-rockchip', '6.12-LTS')
dirs = [pkg, pkg / 'aarch64']
dirs += [pkg / name for name in layers]
dirs += [pkg / '6.12.114', pkg / '6.12.114/aarch64', prj, prj / 'aarch64']
for name in layers:
    dirs += [prj / name, dev / name]
dirs += [prj / '6.12.114', dev]
patches = [p for d in dirs for p in sorted(d.glob('*.patch')) if p.is_file()]
if not patches:
    raise SystemExit('No Arch R kernel patches resolved')
pathlib.Path(sys.argv[2]).write_text(''.join(str(p.relative_to(root)) + '\n' for p in patches))
print('Resolved %d patches' % len(patches))
PY
# Source pins and patch selection determine this cache; config/module-only
# changes must not discard a completed kernel build.
source_id=$(printf '%s\n' 'archr-6b4904f99bef3fffab490b5ea70ac7de15735885-linux-6.12.114-post-patch-v1' "$(sha256sum "$km/patch-order.txt")" | sha256sum | cut -d' ' -f1)
if [[ ! -f $src/.r36llm-source-id || $(cat "$src/.r36llm-source-id") != "$source_id" ]]; then
    rm -rf "$src" "$build"
    mkdir -p "$build"
    tar -xJf "$archive" -C "$work"
    mkdir -p "$km/patches"
    while IFS= read -r name; do
        patchfile=$archr/$name
        install -D "$patchfile" "$km/patches/$name"
        if grep -qE '^GIT binary patch$|^rename from|^rename to' "$patchfile"; then
            (cd "$src" && git apply --verbose --whitespace=nowarn --unsafe-paths "$patchfile")
        else
            python3 - "$patchfile" "$work/kernel.patch" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(pathlib.Path(sys.argv[1]).read_bytes().replace(b'@TARGET_CPU@', b'cortex-a35').replace(b'@DEVICE@', b'RK3326'))
PY
            patch --batch -d "$src" -p1 < "$work/kernel.patch"
        fi
    done < "$km/patch-order.txt"
    cp "$archr/projects/ArchR/packages/linux-drivers/generic-dsi/sources/panel-generic-dsi.c" "$src/drivers/gpu/drm/panel/"
    printf '\nobj-y += panel-generic-dsi.o\n' >> "$src/drivers/gpu/drm/panel/Makefile"
    rsync -a "$archr/projects/ArchR/devices/RK3326/linux/dts/" "$src/arch/arm64/boot/dts/"
    for dts in "$archr/projects/ArchR/devices/RK3326/linux/dts/rockchip/"rk3326-*.dts; do
        dtb=$(basename "$dts" .dts).dtb
        if ! grep -q "$dtb" "$src/arch/arm64/boot/dts/rockchip/Makefile"; then
            printf 'dtb-$(CONFIG_ARCH_ROCKCHIP) += %s\n' "$dtb" >> "$src/arch/arm64/boot/dts/rockchip/Makefile"
        fi
    done
    printf '%s\n' "$source_id" > "$src/.r36llm-source-id"
fi
baseline=$archr/projects/ArchR/devices/RK3326/linux/linux.aarch64.conf
printf '%s  %s\n' dbff7a0380d973756d1cff855878c5ded85800457b9149f1333da8681a3e0e63 "$baseline" | sha256sum -c -
"$src/scripts/kconfig/merge_config.sh" -m -O "$build" "$baseline" "$root/br2-external/board/r36llm-mainline/linux.fragment"
make -C "$src" O="$build" olddefconfig
python3 - "$root/br2-external/board/r36llm-mainline/linux.fragment" "$build/.config" <<'PY' | tee "$km/fragment-check.txt"
import pathlib, sys
requested = [l for l in pathlib.Path(sys.argv[1]).read_text().splitlines() if l.startswith('CONFIG_') or (l.startswith('# CONFIG_') and l.endswith(' is not set'))]
resolved = set(pathlib.Path(sys.argv[2]).read_text().splitlines())
for line in requested:
    if line not in resolved:
        raise SystemExit('Fragment option not resolved: ' + line)
    print('PASS ' + line)
print('PASS %d fragment settings' % len(requested))
PY
cp "$build/.config" "$km/.config"
python3 "$src/scripts/diffconfig" "$baseline" "$build/.config" > "$km/config.diff"
make -C "$src" O="$build" -j"${JOBS:-6}" DTC_FLAGS=-@ Image modules rockchip/rk3326-gameconsole-eeclone.dtb
release=$(make -s -C "$src" O="$build" kernelrelease)
fetch_git https://github.com/archr-linux/archr-joypad.git 4a8392c1a15a9cf2cab43750c3246d53d6410301 "$work/archr-joypad"
make -C "$src" O="$build" M="$work/archr-joypad" DEVICE=RK3326 -j"${JOBS:-6}" modules
# Keep module names on the Linux volume; NTFS case folding corrupts some pairs.
stage=$work/modules
rm -rf "$stage"
make -C "$src" O="$build" INSTALL_MOD_PATH="$stage" modules_install
install -D "$work/archr-joypad/archr-singleadc-joypad.ko" "$stage/lib/modules/$release/extra/archr-singleadc-joypad.ko"
rm -f "$stage/lib/modules/$release/build" "$stage/lib/modules/$release/source"
depmod -b "$stage" "$release"
vermagic=$(modinfo -F vermagic "$stage/lib/modules/$release/extra/archr-singleadc-joypad.ko")
[[ $vermagic == "$release "* ]]
printf 'Kernel release: %s\nJoypad vermagic: %s\n' "$release" "$vermagic" | tee "$km/module-check.txt"
modinfo "$stage/lib/modules/$release/extra/archr-singleadc-joypad.ko" > "$km/joypad-modinfo.txt"
printf '%s\n' "$release" > "$km/kernelrelease"
tar -czf "$art/modules.tar.gz" -C "$stage" lib
cp "$build/arch/arm64/boot/Image" "$art/Image"
cp "$build/arch/arm64/boot/dts/rockchip/rk3326-gameconsole-eeclone.dtb" "$art/"
cp "$src/COPYING" "$build/System.map" "$build/Module.symvers" "$baseline" "$km/"
cp "$root/br2-external/board/r36llm-mainline/linux.fragment" "$km/"
cp "$archive" "$km/"
git -C "$archr" archive HEAD | gzip -n > "$meta/archr-source.tar.gz"
git -C "$work/archr-joypad" archive HEAD | gzip -n > "$km/joypad-source.tar.gz"
{ aarch64-linux-gnu-gcc --version; dpkg-query -W; } > "$meta/toolchain.txt"
sha256sum "$art/Image" "$art/rk3326-gameconsole-eeclone.dtb" "$art/modules.tar.gz" "$km/.config" > "$km/SHA256SUMS"
