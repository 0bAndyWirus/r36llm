#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
um=$meta/usb-host
mkdir -p "$um"
exec > >(tee "$um/build.log") 2>&1
dtc -@ -I dts -O dtb -o "$art/usb-host-experimental.dtbo" \
    "$root/br2-external/board/r36llm-mainline/usb-host-experimental.dts"
fdtoverlay -i "$meta/panel/rk3326-gameconsole-eeclone-panel8.dtb" \
    -o "$um/rk3326-gameconsole-eeclone-panel8-usb-host.dtb" "$art/usb-host-experimental.dtbo"
dtc -I dtb -O dts -o "$um/rk3326-gameconsole-eeclone-panel8-usb-host.dts" \
    "$um/rk3326-gameconsole-eeclone-panel8-usb-host.dtb"
python3 - "$um/rk3326-gameconsole-eeclone-panel8-usb-host.dtb" <<'PY'
import fdt, pathlib, sys
tree = fdt.parse_dtb(pathlib.Path(sys.argv[1]).read_bytes())
symbols = tree.get_node('/__symbols__')
for name in ('u2phy_otg', 'usb20_otg'):
    node = tree.get_node(symbols.get_property(name).value)
    assert node.get_property('status').value == 'okay'
    if name == 'usb20_otg':
        assert node.get_property('dr_mode').value == 'host'
    print('PASS experimental host overlay:', name, 'okay')
print('UNTESTED: no USB enumeration, VBUS measurement or hardware boot performed')
PY
cp "$root/br2-external/board/r36llm-mainline/usb-host-experimental.dts" "$um/"
sha256sum "$art/usb-host-experimental.dtbo" "$um/"*.dtb > "$um/SHA256SUMS"
