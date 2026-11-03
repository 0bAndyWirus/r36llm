#!/bin/sh
set -eu
TARGET_DIR=${1:?Usage: post-build.sh TARGET_DIR}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MODULES="$REPO/out/bsp/artifacts/modules/lib/modules"
KEY="$REPO/keys/authorized_keys"
[ -d "$MODULES" ] || { echo "r36llm: build the source kernel first with scripts/build.ps1" >&2; exit 1; }
for tool in sfdisk blockdev mkfs.fat; do
    if [ ! -x "$TARGET_DIR/sbin/$tool" ] && [ ! -x "$TARGET_DIR/usr/sbin/$tool" ]; then
        echo "r36llm: missing first-boot tool $tool; rebuild util-linux/dosfstools after changing their configuration" >&2
        exit 1
    fi
done
for bin in "$TARGET_DIR"/usr/bin/llama-*; do
    case "$bin" in */llama-cli|*/llama-bench) ;; *) rm -f "$bin" ;; esac
done
python3 - "$MODULES" "$TARGET_DIR" <<'PY'
import pathlib
import shutil
import sys

roots = list(pathlib.Path(sys.argv[1]).iterdir())
if len(roots) != 1:
    sys.exit("r36llm: expected one source-built kernel module release")
source, target = roots[0], pathlib.Path(sys.argv[2])
version = source.name
deps = {}
for line in (source / "modules.dep").read_text().splitlines():
    module, children = line.split(":", 1)
    deps[module] = children.split()
builtins = {pathlib.PurePosixPath(p).stem.replace("-", "_")
            for p in (source / "modules.builtin").read_text().splitlines()}
module_root = target / "lib/modules"
if module_root.exists():
    shutil.rmtree(module_root)
config = target / "etc/r36llm"
config.mkdir(parents=True, exist_ok=True)

def collect(names):
    order, seen = [], set()
    def visit(module):
        path = pathlib.PurePosixPath(module)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("unsafe module path: " + module)
        if module in seen:
            return
        seen.add(module)
        for child in deps[module]:
            visit(child)
        order.append(module)
    for name in names:
        matches = [p for p in deps if pathlib.PurePosixPath(p).name == name + ".ko"]
        if len(matches) == 1:
            visit(matches[0])
        elif name.replace("-", "_") not in builtins:
            raise ValueError("required module is neither built-in nor built: " + name)
    for module in order:
        destination = module_root / version / module
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / module, destination)
    return "".join("/lib/modules/%s/%s\n" % (version, m) for m in order)

for group, names in (
    ("gadget", ("dwc2", "usb_f_ncm", "usb_f_rndis")),
    ("net", ("dwc2", "ax88179_178a", "r8152", "asix", "cdc_ether", "cdc_ncm", "smsc95xx")),
    ("exfat", ("exfat",)),
):
    suffix = "-module.txt" if group == "exfat" else "-modules.txt"
    (config / (group + suffix)).write_text(collect(names))
PY
if [ "${R36LLM_RELEASE:-0}" != 1 ] && [ -s "$KEY" ]; then
    install -d -m 0700 "$TARGET_DIR/root/.ssh"
    install -m 0600 "$KEY" "$TARGET_DIR/root/.ssh/authorized_keys"
else
    rm -f "$TARGET_DIR/root/.ssh/authorized_keys"
    echo "r36llm: no keys/authorized_keys; SSH password login remains available (r36llm)" >&2
fi
rm -rf "$TARGET_DIR/etc/dropbear"
ln -sfn /data/r36llm/ssh "$TARGET_DIR/etc/dropbear"
# Windows bind mounts do not preserve executable bits reliably.
install -d "$TARGET_DIR/etc/r36llm/defaults"
install -m 0644 "$REPO/card/r36llm/config.ini" "$REPO/card/r36llm/prompts.txt" \
    "$REPO/card/r36llm/output-keep-en-fr.txt" "$TARGET_DIR/etc/r36llm/defaults/"
chmod 0755 "$TARGET_DIR"/etc/init.d/S* "$TARGET_DIR"/usr/sbin/r36-*
