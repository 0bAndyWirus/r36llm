#!/bin/sh
set -eu
TARGET_DIR=${1:?Usage: post-build.sh TARGET_DIR}
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
ARCHIVE="$REPO/vendor/harvest/modules-4.4.189.tar.gz"
KEY="$REPO/keys/authorized_keys"
[ -f "$ARCHIVE" ] || { echo "r36llm: missing vendor module archive: $ARCHIVE; see README \"2. Harvest the vendor files\"" >&2; exit 1; }
for bin in "$TARGET_DIR"/usr/bin/llama-*; do
    case "$bin" in */llama-cli|*/llama-bench) ;; *) rm -f "$bin" ;; esac
done
python3 - "$ARCHIVE" "$TARGET_DIR" <<'PY'
import pathlib
import sys
import tarfile

archive, target = sys.argv[1], pathlib.Path(sys.argv[2])
version = "4.4.189"
try:
    with tarfile.open(archive, "r:gz") as tar:
        members = {m.name.removeprefix("./"): m for m in tar.getmembers() if m.isfile()}
        dep_member = members.get(version + "/modules.dep")
        if dep_member is None:
            raise ValueError("missing " + version + "/modules.dep")
        deps = {}
        for line in tar.extractfile(dep_member).read().decode().splitlines():
            if line.strip():
                module, children = line.split(":", 1)
                deps[module] = children.split()

        def find(name):
            matches = [p[len(version) + 1:] for p in members
                       if p.startswith(version + "/") and pathlib.PurePosixPath(p).name == name]
            if len(matches) != 1:
                raise ValueError("expected one %s, found %d" % (name, len(matches)))
            return matches[0]

        dwc, ncm, rndis, exfat = map(find, ("dwc2.ko", "usb_f_ncm.ko", "usb_f_rndis.ko", "exfat.ko"))
        order, active, visited = [], set(), set()

        def visit(module):
            path = pathlib.PurePosixPath(module)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("unsafe module path: " + module)
            if module in visited:
                return
            if module in active:
                raise ValueError("module dependency cycle: " + module)
            if module not in deps or version + "/" + module not in members:
                raise ValueError("missing module or dependency entry: " + module)
            active.add(module)
            for child in deps[module]:
                visit(child)
            active.remove(module)
            visited.add(module)
            order.append(module)

        visit(dwc)
        if order[0] != dwc:
            raise ValueError("dwc2 has dependencies; cannot put it first safely")
        for module in (ncm, rndis):
            for child in deps.get(module, []):
                visit(child)
        visit(ncm)
        visit(rndis)
        gadget_order = list(order)
        order.clear()
        visited.clear()
        visit(dwc)
        for name in ("ax88179_178a.ko", "r8152.ko", "asix.ko", "cdc_ether.ko", "cdc_ncm.ko", "smsc95xx.ko"):
            visit(find(name))
        net_order = list(order)
        module_root = target / "lib/modules" / version
        for module in dict.fromkeys(gadget_order + net_order + [exfat]):
            destination = module_root / module
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(tar.extractfile(members[version + "/" + module]).read())
        config = target / "etc/r36llm"
        config.mkdir(parents=True, exist_ok=True)
        for name, modules in (("gadget", gadget_order), ("net", net_order)):
            (config / (name + "-modules.txt")).write_text(
                "".join("/lib/modules/%s/%s\n" % (version, m) for m in modules))
        (config / "exfat-module.txt").write_text("/lib/modules/%s/%s\n" % (version, exfat))
except (OSError, ValueError, KeyError, tarfile.TarError) as error:
    sys.exit("r36llm: module harvesting failed: " + str(error))
PY
if [ -s "$KEY" ]; then
    install -d -m 0700 "$TARGET_DIR/root/.ssh"
    install -m 0600 "$KEY" "$TARGET_DIR/root/.ssh/authorized_keys"
else
    rm -f "$TARGET_DIR/root/.ssh/authorized_keys"
    echo "r36llm: no keys/authorized_keys; SSH password login remains available (r36llm)" >&2
fi
# Replace Dropbear's default /var/run symlink after package installation.
rm -rf "$TARGET_DIR/etc/dropbear"
ln -sfn /data/r36llm/ssh "$TARGET_DIR/etc/dropbear"
