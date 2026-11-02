# Linux 6.12 on the Panel 8 R36S clone

## Status and scope

This is a **source-audited preparation plan**, not a working mainline image. The target is `G80CA-MB V1.3-20251212 Panel 8`, RK3326, 1 GiB RAM. No kernel build, panel-overlay generation, SD write, device connection, or hardware test was performed for this preparation. The existing Linux 4.4 image and its bootloader remain the fallback.

The prepared files are in [`br2-external/board/r36llm-mainline/`](../br2-external/board/r36llm-mainline/):

- `linux.fragment`: 11 justified changes to the pinned Arch R config.
- `boot.ini`: source for a mainline U-Boot `boot.scr`, with explicit Panel 8 overlay application and external `uInitrd` loading.
- `README-mainline.md`: baseline values, unchanged requirements, source checksum, and merge instructions.

The existing build/deploy scripts still target the vendor 4.4 route. Do not use them to install these draft files onto the fallback card.

## Source lock

Use these revisions together; do not replace them with branch heads:

|Input|Pinned source|
|---|---|
|Arch R integration|[`6b4904f99bef3fffab490b5ea70ac7de15735885`](https://github.com/archr-linux/Arch-R/tree/6b4904f99bef3fffab490b5ea70ac7de15735885)|
|Kernel recipe|[`projects/ArchR/packages/linux/package.mk`](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux/package.mk): RK3326 resolves to Linux **6.12.114**, archive SHA256 `7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3`|
|Kernel baseline|[`linux.aarch64.conf`](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/linux/linux.aarch64.conf), SHA256 `dbff7a0380d973756d1cff855878c5ded85800457b9149f1333da8681a3e0e63`|
|Board patches|[`devices/RK3326/patches/linux/`](https://github.com/archr-linux/Arch-R/tree/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/patches/linux)|
|Common patches|[`packages/linux/patches/`](https://github.com/archr-linux/Arch-R/tree/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux/patches), plus any matching common layers resolved by Arch R's package machinery|
|Clone base DTS|[`rk3326-gameconsole-eeclone.dts`](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/linux/dts/rockchip/rk3326-gameconsole-eeclone.dts)|
|Generic panel driver|[`generic-dsi` package](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux-drivers/generic-dsi/package.mk) and the [in-tree source copy](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux-drivers/generic-dsi/sources/panel-generic-dsi.c)|
|External joypad|[Arch R package](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux-drivers/archr-joypad/package.mk), pin [`4a8392c1a15a9cf2cab43750c3246d53d6410301`](https://github.com/archr-linux/archr-joypad/tree/4a8392c1a15a9cf2cab43750c3246d53d6410301)|
|Mainline U-Boot integration|[RK3326 package](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/packages/u-boot/package.mk), upstream **v2025.10**, with its pinned Arch R patch, defconfig, and source overlays|
|Boot firmware|[rkbin package](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/tools/rkbin/package.mk), pin [`74213af1e952c4683d2e35952507133b61394862`](https://github.com/rockchip-linux/rkbin/tree/74213af1e952c4683d2e35952507133b61394862)|
|Panel generator|[`generator.sh`](https://github.com/loddv/Arch-R-R36S/blob/fe8aa3d3497e0937ea27123749fcf1a306f84dec/config/mipi-generator/generator.sh) and [`archr-dtbo.py`](https://github.com/loddv/Arch-R-R36S/blob/fe8aa3d3497e0937ea27123749fcf1a306f84dec/config/mipi-generator/archr-dtbo.py), commit **fe8aa3d3497e0937ea27123749fcf1a306f84dec**|
|Exact board's vendor input|[`G80CA-MB V1.3-20251212 Panel 8/rk3326-r36s-linux.dtb`](https://github.com/loddv/Arch-R-R36S/blob/fe8aa3d3497e0937ea27123749fcf1a306f84dec/config/archr-dts/clone/G80CA-MB%20V1.3-20251212%20Panel%208/rk3326-r36s-linux.dtb)|

The baseline config header says Linux 6.12.79. That is not the selected kernel version: the recipe selects 6.12.114 for RK3326. Keep a manifest with archive hashes, patch application order, final `.config`, DTBs, overlay, module hashes, firmware hashes, and toolchain version for each experimental image.

## Kernel and panel preparation

### 1. Preserve the known-good system — 1–2 hours

1. Shut down and remove the 4.4 card. Make a whole-card backup and record its checksum. Label the physical card **4.4 fallback**; do not leave it in a reader during flashing.
2. Preserve the exact board's stock `rk3326-r36s-linux.dtb` locally, with a checksum and board photograph. It is the input for panel conversion, not a mainline DTB. Do not publish a harvested binary without checking its distribution terms.
3. Use a second card in TF1 and leave TF2 empty for the first boot. This avoids ambiguous MMC enumeration and the current init scripts selecting another card's partition 3.
4. Record the 4.4 app, kernel, CPU mode, thread count, model hash, and benchmark settings for a later comparison. Do not benchmark or modify a device that another task is using.

### 2. Reproduce the patched kernel source — 0.5–1 day

Work in a new Linux filesystem/build directory, not the active vendor-kernel Docker volumes. Keep any source extraction off case-insensitive Windows directories.

1. Check out the exact Arch R commit. Download Linux 6.12.114 and verify the recipe's SHA256 before extraction.
2. Reproduce the package patch selection, not merely the files in `RK3326/patches/linux`. The recipe sets `PKG_PATCH_DIRS="${LINUX} mainline ${DEVICE} default"`, appends `mainline-rockchip` for RK devices, and appends `6.12-LTS` for this release. Record the files actually resolved and their order; let Arch R's machinery supply that manifest if porting it into Buildroot.
3. Preserve the common gpiolib compatibility and input-polldev patches needed by the external joypad. Retain the RK3326 panel, PMIC/gauge, role-switch/DWC2, and SoC/PX30S fixes. The RK3326 stack includes battery fixes `010`, `040`–`043` and gadget/reset fixes `037`–`039`; starting from vanilla 6.12 omits them.
4. Reproduce `post_patch()` in the kernel recipe: copy its `panel-generic-dsi.c` into `drivers/gpu/drm/panel/` and add its `obj-y` entry, then copy the RK3326 DTS source tree into `arch/arm64/boot/dts/` and register the custom DTBs. The generic panel driver is not supplied by a config option alone.
5. Merge `linux.fragment` over `linux.aarch64.conf` as described in the board README, then run `olddefconfig`. Keep the resolved config and inspect every requested setting before compiling. Do not run the original Arch R `pre_make_target()` unmodified: it overwrites `INITRAMFS_SOURCE` with its own embedded initramfs.
6. Later, build `Image`, DTBs with symbol support (`DTC_FLAGS=-@`), and modules. Confirm `__symbols__` in the clone DTB; the generated panel overlay references labels including `joypad` and may reference `saradc`.
7. Build `archr-singleadc-joypad.ko` from the pinned external driver using that kernel's build tree. Arch R's driver Makefile builds it as a module; setting an unrelated `JOYSTICK_*` option will not provide it. Run `depmod` on the staged module tree and include this module and its dependencies in the initramfs, with an explicit load before the app starts. Never reuse 4.4 modules (`MODVERSIONS=y` in the baseline).

This preparation verified all 11 fragment symbols against the actual pinned file: **11 changed values, zero absent symbols**. It also checked **67 unchanged requirement symbols**, all already `y`. This is a text-level source comparison; `olddefconfig` resolution and compilation remain future gates, not completed checks.

### 3. Generate the exact Panel 8 overlay — 2–4 hours

The clone DTS's default `panel_description` describes a 720×720 mode. It is **not** a substitute for the target's 640×480 Panel 8 timings and initialization commands. A boot without the correct overlay is not a valid display test.

1. Check out loddv/Arch-R-R36S at the pinned commit. Install the generator's dependencies in an isolated environment: `dtc`, Python 3, and the Python `fdt` package. Record the dependency versions.
2. Compare the preserved stock DTB with the exact-board input listed above. If they differ, use the preserved board DTB in a separate local copy of that board directory and retain both hashes. Do not choose an overlay merely because another board also says “Panel 8”.
3. Run `bash config/mipi-generator/generator.sh` from that checkout. It scans board directories and generates six joypad/audio variants per board. Require the log to show no failures; the script uses `set +e`, so process exit status alone is not a sufficient check.
4. Select the default clone result:
   `config/mipi-generator/output/clone/G80CA-MB_V1.3-20251212_Panel_8.dtbo`.
   The generator replaces spaces with underscores. Clone defaults to the K36/single-ADC joypad. Do not select `JPmm` unless hardware evidence proves a different ADC layout; the alternative flags also change input/audio behavior, not just the panel.
5. Decompile the output and inspect its panel timings/initialization, GPIO/reset polarity, rotation, and joypad/audio overrides. Apply it offline with `fdtoverlay` to the newly built `rk3326-gameconsole-eeclone.dtb`. Require success and inspect the merged result; this also checks generator/base-DTS compatibility across the two pinned repositories.
6. Copy the chosen overlay to `/overlays/mipi-panel.dtbo` on the experimental FAT partition. Keep its original filename and input/output checksums in the manifest. Do not copy the legacy vendor DTB into `/dtbs/` as the mainline base tree.

## U-Boot, firmware, and boot flow

### 4. Build the matching loader — 0.5–1 day

Use Arch R's RK3326 **mainline U-Boot v2025.10** package, not `Clone-u-boot` and not Arch R's separate `u-boot-legacy` image. The package depends on the legacy package for other board variants, but `clone_uboot.bin` is assembled from the v2025.10 build. Preserve the package's K36 patch, `rk3326-handheld_defconfig`, and source DTS/includes.

The pinned [loader helper](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/bootloader/rkhelper) uses:

- Rockchip `rk3326_ddr_333MHz_v2.11.bin` for DDR initialization, packed as px30/rksd and followed by `rk3326_miniloader_v1.40.bin`.
- `rk3326_bl31_v1.34.elf` as EL3/TF-A runtime firmware in `trust.img` at address `0x00010000`. The helper disables BL32 (`SEC=0`); do not import a vendor BL32 by assumption.
- `loaderimage --pack --uboot` for `u-boot-dtb.bin`, at load address `0x00200000`.

This route still contains rkbin binaries. It does not build upstream TF-A from source and is not blob-free. Preserve firmware licenses/notices with any distribution. Linux needs working PSCI/secure-firmware handoff (`ARM_PSCI_FW=y` already); changing BL31 independently is a separate port, not part of this plan.

**DDR is a migration risk for an LLM.** The rkbin package retunes the nominal 333 MHz DDR blob to **666 MHz** by default and retains a stock-333 copy. Its comments report cold-training failures at 786 MHz and some clones failing at 666 MHz. Start the first spare-card boot with `clone_uboot.bin.ddr333`, then evaluate the faster loader separately. The package's UART5 loader inherits the retuned DDR settings; its `.ddr333` file is the default-UART variant, not a UART5+333 combination. Build that combined variant explicitly if early UART5 diagnostics are needed. Do not mistake missing UART2 messages for failed Linux boot: the clone DTS uses UART5 as Linux `ttyS2`.

Mainline has no equivalent working PX30 DMC scaling in this integration according to the rkbin recipe; memory can remain at its boot frequency. Recheck sustained inference and stability at the selected DDR clock rather than carrying over 4.4 performance expectations.

### 5. Install a compiled script and boot files — 2–4 hours

Arch R's pinned [U-Boot defconfig](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/packages/u-boot/sources/configs/rk3326-handheld_defconfig) sets:

```text
CONFIG_BOOTCOMMAND="bootmeth order script; bootflow scan -b"
CONFIG_OF_LIBFDT_OVERLAY=y
```

Its normal [clone script](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/packages/u-boot/config/clone_boot.ini) selects a board by ADC and calls `sysboot`; the [extlinux config](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/packages/u-boot/config/extlinux/extlinux.conf) uses `FDTDIR` and `FDTOVERLAYS`. That is a supported alternative, but it expects Arch R's root/storage flow and has no external initrd entry as shipped.

For this initramfs experiment, use the prepared **explicit script** instead:

```sh
mkimage -A arm64 -O linux -T script -C none -n r36llm-mainline \
  -d br2-external/board/r36llm-mainline/boot.ini boot.scr
```

Install this file tree on p1:

```text
/Image
/uInitrd
/boot.scr
/dtbs/rk3326-gameconsole-eeclone.dtb
/overlays/mipi-panel.dtbo
```

The script receives `devtype`, `devnum`, and `distro_bootpart` from the MMC bootflow scan. It fixes the board selection to `eeclone`, loads every required file, expands the DTB by 256 KiB, and applies the overlay before `booti`. A missing file or failed overlay prevents that script from booting Linux. Do not install competing `boot.scr`/`boot.ini`/extlinux entries from another distro on the experiment's boot partition.

The draft uses physical addresses `0x02000000` (DTB), `0x08000000` (overlay), `0x09000000` (Image), and `0x20000000` (initrd). Before booting, check actual image sizes, DRAM/reserved ranges, and U-Boot's relocation/LMB layout for overlap. These are proposed addresses for this 1 GiB board, not a hardware-verified map.

`uInitrd` remains the Buildroot **gzip cpio in a U-Boot legacy ramdisk wrapper**. Check the resolved U-Boot config for `LEGACY_IMAGE_FORMAT=y`, `CMD_BOOTI`, `CMD_FDT`, overlay support, FAT loading, and script scanning. `booti` receives the ramdisk **header address without `:size`**, so U-Boot interprets the legacy header and passes its payload to Linux. A raw `address:size` initrd path would instead pass the wrapper bytes as payload. Linux's new `RD_GZIP=y` unpacks the resulting gzip cpio. Check wrapper metadata/CRC with host tools before first boot; if adapting to an unwrapped `rootfs.cpio.gz`, change both installation and boot arguments deliberately rather than mixing formats.

The command line uses `rdinit=/init`, verbose logs, `console=ttyS2,115200`, `console=tty1`, and `net.ifnames=0`. It does not use Arch R's `boot=`, squashfs `root=`, or `disk=` arguments. Keep thermal protection enabled; do not copy `nowatchdog`/`mitigations=off` performance flags merely because Arch R uses them.

## Spare-card layout

The current [`genimage.cfg`](../br2-external/board/r36llm/genimage.cfg) is a reference only. Prepare a **separate** mainline image definition when implementing the build:

|Region|Existing 4.4 image|Proposed mainline spare card|
|---|---|---|
|Partition table|MBR, signature `0x52333653`|Keep MBR and signature if retaining current grow scripts|
|Raw loader|Separate idbloader at sector 64, U-Boot at 16384, trust at 24576|Arch R unified `clone_uboot.bin*` starts at sector **64**; its internal U-Boot/trust offsets are relative to this start|
|Loader internal offsets|Not applicable to the three-file writes|U-Boot at relative sector 16320, trust at 24512: absolute sectors remain **16384** and **24576**|
|U-Boot environment|Vendor reserved area at 1 MiB|Pinned mainline config uses `ENV_OFFSET=0x4000`, `ENV_SIZE=0x4000` (16–32 KiB); reserve it and avoid `saveenv` during initial bring-up|
|p1|Start 16 MiB, 128 MiB FAT32 `R36BOOT`, vendor boot.ini and DTB|Keep geometry/label; use the file tree above and compiled `boot.scr`|
|p2|512 MiB swap `R36SWAP`|Keep swap, **not** an Arch R squashfs/ext4 root partition|
|p3|Initial 128 MiB FAT32 `R36DATA`, grows on first boot|Keep p3 and current initialization markers/labels if reusing `S02data`/`r36-grow-data`|
|Root filesystem|External Buildroot initramfs|External Buildroot initramfs; no disk rootfs required|

Do not write the combined loader at sector 0 or sector 16384. Its file offset zero corresponds to **disk sector 64**. Check its length fits entirely before p1; an oversized trust/combined image must fail image assembly rather than overwrite the FAT partition. Do not retain the old vendor loader components alongside the new combined loader as a second boot chain.

The [Arch R updater](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/bootloader/update.sh) preserves the first 32 KiB before installing its combined loader. It is evidence for the offset, **not** an installer to run on an r36llm card: its boot/root/storage assumptions and update behavior differ.

Current `S02data` scans `/dev/mmcblk*p3` and `S03swap` derives p2 from the mounted p3. Mainline DTS aliases differ from assumptions based on `mmcblk0`; keep only one card inserted and verify the selected disk. Preserve the grow tool's disk signature, labels, and marker contract, or port that validation as part of the new image target. Never run a grow/format path on the preserved fallback card. Copy a model only after initialization finishes.

## Application and userspace changes

Allow **0.5–1 day** for these changes and tests after basic boot. They are identified here, not implemented by this board-preparation change.

|Area|Current code / behavior|Mainline action|
|---|---|---|
|Keymap|Vendor evdev mapping in `app/src/input.cpp`|Use the separately developed `keymap=mainline` profile. The clone DTS reports `BTN_DPAD_*`, A=`BTN_EAST`, B=`BTN_SOUTH`, X=`BTN_NORTH`, Y=`BTN_WEST`, F=`BTN_MODE`, normal `BTN_SELECT`/`BTN_START`, and shoulder buttons. Use header constants, not the sometimes incorrect numeric comments in the DTS. Validate press, release, repeat, chords, analog axes, and the separate PMIC power-key device.|
|Framebuffer|`app/src/fb.cpp` opens `/dev/fb0`, queries both fb ioctls, mmaps `smem_len`, accepts 16/32 bpp, and uses a 640×480 logical canvas|Keep DRM fbdev emulation; no DRM/KMS rewrite is required unless the fbdev interface fails. Check mode/rotation, stride, channel bitfields, offsets, mmap writes appearing on screen, and tty restoration. `/dev/dri/card0` alone does not satisfy the app. Do not assume a blank display is an app bug before validating the panel overlay.|
|Backlight|`device.cpp` fixes `/sys/class/backlight/backlight`, scales against `max_brightness`|The clone DTS's `backlight` node uses `pwm-backlight`, so the same class path is expected, not yet observed. Verify it. If names differ across board targets, discover a valid PWM backlight via sysfs rather than hardcoding a guessed mainline path. Test brightness 10–100%, zero for screen-off, wake, and shutdown.|
|Battery|`device.cpp` reads `/sys/class/power_supply/battery`; `ac/online` and `usb/online` are also fixed|The RK817 driver registers `rk817-battery` and `rk817-charger`. Discover supplies by `type` (Battery vs USB/Mains), use the selected supply's capacity/status/voltage/current, and tolerate absent optional files. Do not treat the DTS's `simple-battery` node as the exported supply name. Revalidate low-battery shutdown before unattended use.|
|Charging|Status is used for charging indication; separate online flags describe AC/USB|Keep Arch R's external-charger reporting patch `043`: these clones can charge without RK817 VBUS detection. A false `rk817-charger/online` does not prove the pack is discharging. Compare status and signed current with plug/unplug tests. The DTS's nominal 4000 mAh capacity is not a measurement of this pack.|
|Thermal|`device.cpp` enumerates every `thermal_zone*`, reads `type` and millidegrees, and shows the hottest valid zone|No fixed zone index needs changing. Inherited PX30 DT names are expected to include `soc-thermal` and `gpu-thermal`, not the vendor `cpu-thermal` naming; inspect the final patched DT and live `type` files. Verify values/trips/cooling state before inference.|
|CPU modes|App maps performance/balanced/saver to performance/ondemand/powersave and writes `cpu*/cpufreq/scaling_governor`|All three governors and `CPUFREQ_DT` are enabled in the base config. Verify available governors, policy links, frequency/OPP limits, and thermal throttling. Re-measure settings; do not copy vendor OPP/thermal tuning into the new DTS.|
|Early tuning|`S05perf` writes performance to CPU and every devfreq governor before app settings|The CPU paths can remain compatible; mainline devfreq devices and DDR control differ. Check each target's available governors, leave unsupported devices alone, and do not assume this script raises DDR speed. The later app-selected CPU mode still needs checking.|
|Configuration helper|`r36-config` reads config.ini and has no hardware paths|No direct sysfs port is required. Keep its config/default behavior and set `keymap=mainline` in this image's configuration without changing the 4.4 card's profile.|
|Init/console|Buildroot initramfs; current inittab starts app on tty1 and vendor getty on `ttyFIQ0`|Preserve generated `/init` and explicit devtmpfs/proc/sysfs mounts. Replace the vendor serial getty with the verified mainline UART (`ttyS2` for the pinned clone DTS); tty1 still hosts the app.|
|Module staging|Current post-build hook consumes `out/bsp/artifacts/modules`, selects vendor networking/gadget/exFAT modules|Give mainline its own artifact input. Built-in networking/exFAT must not require absent `.ko` files; include/load the external joypad. Do not mix module trees or overwrite 4.4 artifacts.|
|Network naming|App displays eth0; startup scripts configure Ethernet and experimental gadget|Keep the draft's `net.ifnames=0` initially. Verify the actual adapter/interface, DHCP, SSH keys, and reboot persistence. Gadget support being compiled in does not establish a usable UDC.|

### USB host first, gadget later

The clone DTS enables the PHY host port but explicitly disables `u2phy_otg`; `usb20_otg` itself is enabled. Therefore even the known ASIX adapter on the physically labeled OTG connector must be tested under mainline. Built-in adapter support cannot fix a disabled PHY or incorrect VBUS wiring.

If host mode on that connector does not probe, inspect the merged DT, controller/PHY links, board ID/VBUS pins, dmesg, and USB topology. A board-specific DT change enabling the correct PHY and choosing safe host mode may be required. Do not blindly enable the OTG port or force peripheral mode while powered by a host adapter. Establish the power wiring first and avoid back-feeding either PC or handheld.

Only after stable host SSH should device mode be attempted: enable the correctly wired OTG PHY in a reviewed board DT/overlay, verify role/VBUS handling, confirm a UDC under `/sys/class/udc`, mount configfs, and bind NCM/RNDIS using `r36-gadget`. The required kernel options are already `y`; DTS/electrical behavior is the unresolved prerequisite. The first mainline milestone does not claim plain-cable networking.

## Hardware acceptance on the spare card

Allow **1–2 days** of bring-up and repeat testing; panel or USB wiring faults can add several days. The total first-pass engineering estimate is **3–5 working days**, excluding long builds/downloads and unknown hardware faults. These are planning estimates, not measured completion times.

1. **Offline gate:** check source hashes, final config, matching module vermagic, initramfs contents/`/init`, legacy ramdisk metadata, DTB symbols, offline overlay application, combined-loader offsets/length, partition table/signature, and boot file hashes. Check the exact removable-card identity and image size before flashing; verify the written image afterward.
2. **First boot:** only the spare TF1 card is inserted. Capture UART5 if safely accessible with 3.3 V-compatible equipment and known pinout; do not assume vendor FIQ console behavior. Stop on boot loops, a hot blank screen, or repeated DDR resets. No inference yet.
3. **Kernel/initramfs:** record `uname -a`, `/proc/cmdline`, `/proc/mounts`, `/proc/meminfo`, `dmesg`, `/proc/swaps`, and the boot log. Root must be the RAM initramfs, p2 swap must belong to the spare card, and `/data` must be the intended p3. Reboot and prove data initialization is not repeated.
4. **Display/input:** confirm `/dev/fb0` and a readable 640×480 display; exercise color/stride/rotation, all buttons and chords using `keymap=mainline`, power press/hold, brightness, screen-off/wake, and console cleanup after app exit. Keep a recovery autorun/serial route if input is wrong.
5. **Power/thermal:** inspect all power-supply `type`/status/current/voltage files and thermal `type`/temperature/trips. Test charger plug/unplug and safe shutdown. Compare reported voltage/capacity with the fallback system; retain critical-battery protection rather than disabling it to get through a test.
6. **USB host rescue:** use the existing ASIX adapter, verify driver binding, network address, DHCP/SSH, file transfer (`scp -O` while no sftp-server is installed), and reconnect after reboot. Record whether the physically labeled OTG port needed a DT change. Test the other shipped driver families when adapters are available; do not claim physical adapter coverage from config inspection.
7. **Short inference:** after display, charging, and thermal protection work, copy one model to the initialized data partition. Use fixed model/prompt/settings and compare correctness and peak RAM with 4.4. Begin with short generations while watching temperature and throttling.
8. **Sustained/regression:** repeat the established thermal benchmark methodology, including 2/3/4 threads and each CPU mode, and record DDR loader selection. Test reboot, poweroff, persistence, SD growth, and cold boot several times. Validate any 666 MHz DDR variant separately; never infer reliability from one warm reboot.
9. **Fallback drill:** power off, remove the spare, insert only the preserved 4.4 card, and confirm the known-good system returns unchanged. There is no need to flash firmware into internal storage for this experiment. Keep mainline artifacts and results separate until all acceptance gates pass.

If the screen stays blank, restore the fallback card rather than repeatedly writing different loaders to it. Diagnose in order: BootROM/DDR/miniloader, BL31/U-Boot, file loading and overlay, kernel/initramfs, then DRM/panel and app. A successful compilation or offline DT merge does not prove the hardware boots.
