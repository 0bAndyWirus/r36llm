# Mainline RK3326 board preparation

These files prepare a separate Linux 6.12 experiment. They are not wired into `scripts/build.ps1`, do not replace the 4.4 board, and have not been boot-tested. See [the migration plan](../../../docs/mainline.md) before building or flashing anything.

## Pinned inputs

All Arch R paths below refer to commit [`6b4904f99bef3fffab490b5ea70ac7de15735885`](https://github.com/archr-linux/Arch-R/tree/6b4904f99bef3fffab490b5ea70ac7de15735885).

- [Kernel recipe](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux/package.mk): RK3326 selects Linux **6.12.114**, SHA256 `7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3`. The config header still says 6.12.79; the recipe, not that stale header, selects the source release.
- [Baseline config](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/linux/linux.aarch64.conf): raw-file SHA256 `dbff7a0380d973756d1cff855878c5ded85800457b9149f1333da8681a3e0e63`.
- [RK3326 patches](https://github.com/archr-linux/Arch-R/tree/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/patches/linux) and the recipe's common patch layers are required. This is a patched mainline route, not vanilla kernel.org support.
- [Clone DTS](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/linux/dts/rockchip/rk3326-gameconsole-eeclone.dts).
- [U-Boot recipe](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/packages/u-boot/package.mk), [defconfig](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/devices/RK3326/packages/u-boot/sources/configs/rk3326-handheld_defconfig), and [loader assembly](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/bootloader/rkhelper).

## Config delta and evidence

`linux.fragment` has **11 changed settings**. Each setting has its own rationale. The raw pinned config was fetched and parsed on 2026-11-02; all 11 symbols exist and all 11 values differ:

|Symbol (prefix `CONFIG_`)|Pinned baseline|Fragment|
|---|---|---|
|`INITRAMFS_SOURCE`|`"@INITRAMFS_SOURCE@"`|`""`|
|`RD_GZIP`|not set|`y`|
|`USB_NET_DRIVERS`|`m`|`y`|
|`MII`|`m`|`y`|
|`USB_USBNET`|`m`|`y`|
|`USB_NET_AX8817X`|`m`|`y`|
|`USB_NET_AX88179_178A`|`m`|`y`|
|`USB_RTL8152`|`m`|`y`|
|`USB_NET_CDCETHER`|`m`|`y`|
|`USB_NET_CDC_NCM`|`m`|`y`|
|`USB_NET_SMSC95XX`|`m`|`y`|

The USB menu parent and MII helper are included so promoting the drivers does not leave their dependencies modular. Built-in adapters simplify rescue networking; the external joypad still needs a matching module in the initramfs.

These required options already equal `y` and therefore **do not appear in the fragment**:

|Requirement|Verified baseline symbols (all `CONFIG_`, all `y`)|
|---|---|
|External initramfs|`BLK_DEV_INITRD`|
|Device nodes|`DEVTMPFS`, `DEVTMPFS_MOUNT`|
|Boot/data filesystems|`FAT_FS`, `VFAT_FS`, `EXFAT_FS`, `NLS_CODEPAGE_437`, `NLS_ISO8859_1`, `NLS_UTF8`|
|USB host|`USB`, `USB_EHCI_HCD`, `USB_EHCI_HCD_PLATFORM`, `USB_OHCI_HCD`, `USB_OHCI_HCD_PLATFORM`, `PHY_ROCKCHIP_INNO_USB2`|
|Later gadget work|`USB_DWC2`, `USB_DWC2_DUAL_ROLE`, `USB_GADGET`, `USB_ROLE_SWITCH`, `CONFIGFS_FS`, `USB_CONFIGFS`, `USB_CONFIGFS_NCM`, `USB_CONFIGFS_ECM`, `USB_CONFIGFS_RNDIS`|
|Framebuffer app|`DRM`, `DRM_ROCKCHIP`, `ROCKCHIP_VOP`, `ROCKCHIP_DW_MIPI_DSI`, `DRM_FBDEV_EMULATION`, `FB`, `FB_DEVICE`, `FRAMEBUFFER_CONSOLE`, `VT`, `VT_CONSOLE`, `BACKLIGHT_PWM`|
|Input and external joypad dependencies|`INPUT_EVDEV`, `INPUT_POLLDEV`, `INPUT_FF_MEMLESS`, `ROCKCHIP_SARADC`, `INPUT_RK805_PWRKEY`, `MODULES`|
|RK817 battery and charger|`POWER_SUPPLY`, `MFD_RK8XX`, `MFD_RK8XX_I2C`, `REGULATOR_RK808`, `CHARGER_RK817`|
|Thermal protection|`THERMAL`, `THERMAL_OF`, `CPU_THERMAL`, `CPU_FREQ_THERMAL`, `ROCKCHIP_THERMAL`, `THERMAL_GOV_STEP_WISE`|
|CPU clock modes|`CPU_FREQ`, `CPUFREQ_DT`, `CPUFREQ_DT_PLATDEV`, `CPU_FREQ_GOV_PERFORMANCE`, `CPU_FREQ_GOV_ONDEMAND`, `CPU_FREQ_GOV_POWERSAVE`|
|Boot firmware interface|`ARM_PSCI_FW`, `ROCKCHIP_PM_DOMAINS`, `ROCKCHIP_IODOMAIN`|
|SD and RAM userspace|`MMC_DW`, `MMC_DW_ROCKCHIP`, `SWAP`, `PROC_FS`, `SYSFS`, `TMPFS`|

`DEVTMPFS_MOUNT=y` does **not** automount `/dev` when booting an initramfs. Preserve Buildroot's generated `/init` and its explicit devtmpfs mount; also mount proc/sysfs before device discovery. `RD_GZIP` decodes the gzip cpio, not the U-Boot legacy header. The kernel recipe's `panel-generic-dsi.c` copy and `obj-y` Makefile entry are required separately; no `CONFIG_DRM_PANEL_GENERIC_DSI` toggle is provided by that integration.

The clone uses `archr-singleadc-joypad.ko`, not one of the enabled `JOYSTICK_ODROIDGO*` drivers. Use Arch R's [external driver package](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux-drivers/archr-joypad/package.mk), which pins [`4a8392c1a15a9cf2cab43750c3246d53d6410301`](https://github.com/archr-linux/archr-joypad/tree/4a8392c1a15a9cf2cab43750c3246d53d6410301). Compile against this kernel's generated headers and `Module.symvers`; stage it and load it before launching the app. The config enables `MODVERSIONS`, so a 4.4 or stock Arch R module cannot be substituted.

Before a future build, merge in a separate Linux build directory using the patched kernel's own tools:

```sh
# ARCHR is a checkout at the exact commit above; KERNEL is the patched 6.12.114 source.
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p "$KOUT"
"$KERNEL/scripts/kconfig/merge_config.sh" -m -O "$KOUT" \
  "$ARCHR/projects/ArchR/devices/RK3326/linux/linux.aarch64.conf" \
  "$R36LLM/br2-external/board/r36llm-mainline/linux.fragment"
make -C "$KERNEL" O="$KOUT" olddefconfig
```

Then inspect the resolved `.config` for dropped settings. This preparation did **not** run `olddefconfig`, compile a kernel, generate an overlay, or boot hardware. The comparison establishes a nonredundant fragment against the requested baseline, not dependency closure after configuration or hardware support.

## Boot script

`boot.ini` is source for a **compiled `boot.scr`**. Mainline U-Boot's pinned default runs `bootmeth order script; bootflow scan -b`; copying an uncompiled `boot.ini` is not sufficient. The draft directly loads `/Image`, the fixed clone DTB, `/overlays/mipi-panel.dtbo`, and `/uInitrd`; it grows the DTB, applies the overlay, then calls `booti`. No Arch R squashfs/root partition arguments are used.

The alternative upstream flow compiles `clone_boot.ini` to `boot.scr`, selects a DTB by ADC, then invokes extlinux with `FDTOVERLAYS`. Our explicit script avoids that ADC fallback and makes the mandatory overlay and legacy initrd handling visible. Check U-Boot's resolved configuration for `CMD_BOOTI`, `CMD_FDT`, `OF_LIBFDT_OVERLAY`, `LEGACY_IMAGE_FORMAT`, FAT loading, and script bootflow support before using it. Keep the script source, generated script, DTB, overlay, firmware, and hashes together with each experiment.
