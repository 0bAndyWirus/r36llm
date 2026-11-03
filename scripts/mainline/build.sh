#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
input=${1:-/repo/out/uInitrd}
[[ -s $input ]] || { echo "Missing existing Buildroot uInitrd: $input" >&2; exit 1; }
exec > >(tee "$root/out/mainline/logs/build.log") 2>&1
bash "$root/scripts/mainline/build-kernel.sh"
bash "$root/scripts/mainline/build-uboot.sh"
bash "$root/scripts/mainline/build-panel.sh"
if [[ ${R36LLM_USB_HOST:-0} == 1 ]]; then
    bash "$root/scripts/mainline/build-usb-host.sh"
fi
bash "$root/scripts/mainline/repack-initramfs.sh" "$input"
bash "$root/scripts/mainline/assemble-image.sh"
cp "$root/docker/Dockerfile.mainline" "$meta/"
mkdir -p "$meta/build-scripts"
cp -a "$root/scripts/mainline/." "$meta/build-scripts/"
printf 'PASS integrated offline mainline build; no device accessed\n'
