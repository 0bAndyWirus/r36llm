#!/bin/sh
set -eu
RESULTS=/data/r36llm/speedups-state-profile
mkdir -p "$RESULTS"
APP=$(pidof r36llm r36llm.bin || true)
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do printf '%s\t%s\n' "$f" "$(cat "$f")"; done > "$RESULTS/governors"
cleanup() {
 while read -r f governor; do echo "$governor" > "$f"; done < "$RESULTS/governors"
 if [ -n "$APP" ]; then kill -CONT $APP; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$APP" ]; then kill -STOP $APP; fi
{
 sha256sum /tmp/speedups/state/lib/libggml-cpu.so.0 /tmp/speedups/rows/lib/libggml-cpu.so.0 /tmp/speedups/state/lib/libllama.so.0 /data/r36llm/lib/libllama.so.0 /data/r36llm/lib/libggml-cpu.so.0
 LD_LIBRARY_PATH=/tmp/speedups/base/lib /tmp/pool-cost
} > "$RESULTS/identities-and-pool.txt"
for variant in baseline patched; do
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
 while :; do
  hottest=0; for f in /sys/class/thermal/thermal_zone*/temp; do t=$(cat "$f"); if [ "$t" -gt "$hottest" ]; then hottest=$t; fi; done
  if [ "$hottest" -le 50000 ]; then break; fi; sleep 2
 done
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
 case "$variant" in baseline) export GGML_GDN_STATE_GATHER=1 ;; patched) unset GGML_GDN_STATE_GATHER ;; esac
 LD_LIBRARY_PATH=/tmp/speedups/state/lib /tmp/profile /data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf "$RESULTS/$variant" profile > "$RESULTS/$variant.stdout" 2> "$RESULTS/$variant.stderr"
done
sha256sum /data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf /data/r36llm/models/Ternary-Bonsai-1.7B-PQ2_0.gguf > "$RESULTS/models.sha256"
sha256sum "$RESULTS"/* > "$RESULTS/SHA256SUMS"
