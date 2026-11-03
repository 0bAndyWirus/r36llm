#!/usr/bin/env bash
set -euo pipefail

# Run inside the mainline build container, after the symbol-enabled base DTB.
# shellcheck source=scripts/mainline/common.sh
source /repo/scripts/mainline/common.sh
mkdir -p "$art" "$meta/panel"
panel_meta="$meta/panel"
exec > >(tee "$panel_meta/build.log") 2>&1

for cmd in python3 dtc fdtoverlay sha256sum git; do
    command -v "$cmd" >/dev/null || { echo "Missing required tool: $cmd" >&2; exit 1; }
done
python3 - <<'PY'
from importlib.metadata import version
import fdt
assert version('fdt') == '0.3.3', 'Install pinned fdt==0.3.3'
print('Python fdt:', version('fdt'))
PY
python3 --version
dtc --version

commit=fe8aa3d3497e0937ea27123749fcf1a306f84dec
repo=https://github.com/loddv/Arch-R-R36S.git
src="$work/arch-r-r36s"
fetch_git "$repo" "$commit" "$src"
vendor="$src/config/archr-dts/clone/G80CA-MB V1.3-20251212 Panel 8/rk3326-r36s-linux.dtb"
generator="$src/config/mipi-generator/archr-dtbo.py"
base="$art/rk3326-gameconsole-eeclone.dtb"
overlay="$art/mipi-panel.dtbo"
merged="$panel_meta/rk3326-gameconsole-eeclone-panel8.dtb"
test -f "$base" || { echo "Missing base DTB: $base" >&2; exit 1; }
printf '%s  %s\n' 5fbba0469fc8560381b2bf37a67d1a785561f09ee783cf2ff5dc7f32c031adf7 "$vendor" | sha256sum -c -
cp "$src/LICENSE.md" "$panel_meta/upstream-LICENSE.txt"
cp "$generator" "$panel_meta/archr-dtbo.py"
cp "$src/config/mipi-generator/generator.sh" "$panel_meta/generator.sh"
{
    printf 'Repository: %s\nCommit: %s\n' "$repo" "$commit"
    printf 'Input: config/archr-dts/clone/G80CA-MB V1.3-20251212 Panel 8/rk3326-r36s-linux.dtb\n'
    printf 'Generator: config/mipi-generator/archr-dtbo.py; clone default: no option flags (no JPmm or SRs)\n'
    printf 'Python fdt: 0.3.3; wheel SHA256: 6b2fae2e8dfa38e9b0f9666aa001dd25be74e893d293a8d60001438f732e9e47; Apache-2.0\n'
    printf 'Vendor DTB distribution terms are not established by this build; inspect upstream notices before redistribution.\n'
} > "$panel_meta/sources.txt"
sha256sum "$vendor" "$generator" "$src/config/mipi-generator/generator.sh" "$base" > "$panel_meta/input-sha256.txt"
dtc -I dtb -O dts -o "$panel_meta/vendor-input.dts" "$vendor"
# generator.sh uses no flags for the default clone output. Invoke only that
# exact command rather than processing every motherboard and variant.
rm -f "$overlay" "$merged"
python3 "$generator" "$vendor" -o "$overlay" 2>&1 | tee "$panel_meta/generator.log"
test -s "$overlay"
dtc -I dtb -O dts -o "$panel_meta/mipi-panel.dts" "$overlay"
fdtoverlay -i "$base" -o "$merged" "$overlay"
dtc -I dtb -O dts -o "$panel_meta/rk3326-gameconsole-eeclone-panel8.dts" "$merged"

# Inspect actual resolved nodes, including inherited/absent status properties.
# Disabled OTG PHY is deliberately not repaired here: electrical safety and
# port behavior require hardware investigation.
python3 - "$merged" <<'PY' | tee "$panel_meta/audit.txt"
import re
import sys
import fdt

with open(sys.argv[1], 'rb') as stream:
    tree = fdt.parse_dtb(stream.read())
symbols = tree.get_node('/__symbols__')

def symbol(name):
    prop = symbols.get_property(name)
    if prop is None:
        raise RuntimeError('Missing base DT symbol: ' + name)
    return prop.value

def inspect(name, path, expected=None):
    node = tree.get_node(path)
    if node is None:
        raise RuntimeError('Missing node: ' + path)
    status = node.get_property('status')
    value = status.value if status else '(absent; okay by DT convention)'
    print(f'{name}: {path}: status={value}')
    if expected is not None and value != expected:
        raise RuntimeError(f'{name}: expected status {expected}, got {value}')
    return node

panel = inspect('panel', symbol('internal_display'))
assert panel.get_property('compatible').value == 'archr,generic-dsi'
desc = panel.get_property('panel_description').data
modes = [s for s in desc if s.startswith('M ')]
assert modes and all(re.search(r'\bhorizontal=640,', s) and re.search(r'\bvertical=480,', s) for s in modes), 'Panel is not 640x480'
assert any('default=1' in s for s in modes), 'Missing default panel mode'
print('panel modes:', *modes, sep='\n  ')
joy = inspect('joypad', symbol('joypad'), 'okay')
assert joy.get_property('compatible').value == 'archr-singleadc-joypad', 'Unexpected joypad variant'
assert joy.get_property('io-channel-names').value == 'amux_adc'
inspect('ADC', symbol('saradc'), 'okay')
inspect('ADC keys', '/adc-keys', 'okay')
inspect('battery', symbol('battery'))
inspect('RK817 charger', symbol('rk817_charger'))
inspect('USB PHY', symbol('u2phy'), 'okay')
inspect('USB host PHY', symbol('u2phy_host'), 'okay')
inspect('USB OTG PHY', symbol('u2phy_otg'), 'disabled')
inspect('USB OTG controller', symbol('usb20_otg'), 'okay')
inspect('USB EHCI host controller', symbol('usb_host0_ehci'))
inspect('USB OHCI host controller', symbol('usb_host0_ohci'))
inspect('amplified audio', '/rk817-sound-amplified', 'disabled')
inspect('simple audio', '/rk817-sound-simple', 'disabled')
print('Both audio presets remain disabled by the unmodified upstream generator; investigate before relying on audio.')
print('Offline DT audit only: no physical display, input, charging or USB operation has been verified.')
PY
sha256sum "$overlay" "$merged" > "$panel_meta/output-sha256.txt"
