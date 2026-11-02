#!/bin/bash
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OUT="$HERE/../r36llm-harvest"; mkdir -p "$OUT"
say(){ printf '\033c%s\n' "$*" > /dev/tty1; echo "$(date +%T) $*" >> "$OUT/gadget.txt"; }
say "R36LLM probe running..."
KV="$(uname -r)"
{
  uname -a; cat /etc/os-release; ldd --version | head -n1
  cat /proc/cpuinfo /proc/meminfo; free -m
  cat /proc/partitions; mount; echo "--swaps"; cat /proc/swaps; echo "--fs"; cat /proc/filesystems
  for f in name virtual_size bits_per_pixel stride modes; do echo "fb0/$f: $(cat /sys/class/graphics/fb0/$f)"; done
  cat /proc/bus/input/devices; lsmod
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
  for d in /sys/class/devfreq/*; do echo "$d"; cat "$d/available_frequencies" "$d/available_governors"; done
  echo "--udc"; ls /sys/class/udc; cat /sys/class/udc/*/state
  echo "--dwc2"; modinfo dwc2
} > "$OUT/probe.txt" 2>&1
dmesg > "$OUT/dmesg.txt" 2>&1
tar czf "$OUT/modules-$KV.tar.gz" -C /lib/modules "$KV"
sync
# --- cable test ---
for u in /root /home/ark; do mkdir -p "$u/.ssh"; cat "$HERE/r36llm/r36llm.pub" >> "$u/.ssh/authorized_keys"; chmod 700 "$u/.ssh"; chmod 600 "$u/.ssh/authorized_keys"; done
chown -R ark:ark /home/ark/.ssh 2>/dev/null
say "CABLE TEST: plug USB cable R36S OTG port -> PC now (2 min)"
OK=""
for fn in ncm rndis; do
  sh "$HERE/r36llm/r36-gadget" up "$fn" >> "$OUT/gadget.txt" 2>&1 || continue
  if sh "$HERE/r36llm/r36-gadget" wait 60; then OK="$fn"; break; fi
  sh "$HERE/r36llm/r36-gadget" down >> "$OUT/gadget.txt" 2>&1
done
echo "RESULT fn=${OK:-none}" >> "$OUT/gadget.txt"
if [ -n "$OK" ]; then
  IF=$(cat /sys/kernel/config/usb_gadget/r36/functions/$OK.usb0/ifname)
  if command -v dnsmasq >/dev/null; then dnsmasq --port=0 --interface="$IF" --dhcp-range=10.36.0.2,10.36.0.10,12h --pid-file=/tmp/r36dns.pid
  elif command -v udhcpd >/dev/null; then printf 'start 10.36.0.2\nend 10.36.0.10\ninterface %s\noption subnet 255.255.255.0\nlease_file /tmp/u.leases\n' "$IF" > /tmp/u.conf; udhcpd /tmp/u.conf; fi
  systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null || /usr/sbin/sshd
  say "LINK UP ($OK): ssh root@10.36.0.1 or 169.254.36.1 - up 15 min"
  i=0; while [ $i -lt 900 ] && [ ! -e /tmp/r36llm-stop ]; do sleep 1; i=$((i+1)); done
  [ -f /tmp/r36dns.pid ] && kill "$(cat /tmp/r36dns.pid)"; killall udhcpd 2>/dev/null
  sh "$HERE/r36llm/r36-gadget" down >> "$OUT/gadget.txt" 2>&1
fi
dmesg | grep -iE 'dwc2|udc|gadget|usb0' > "$OUT/dmesg-usb.txt"
sync; say "R36LLM probe DONE (cable: ${OK:-FAILED}) - power off now"; sleep 10
