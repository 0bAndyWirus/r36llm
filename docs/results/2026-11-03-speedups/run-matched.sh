#!/bin/sh
set -eu
RESULTS=/data/r36llm/speedups-matched
mkdir -p "$RESULTS"
APP=$(pidof r36llm r36llm.bin || true)
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do printf '%s\t%s\n' "$f" "$(cat "$f")"; done > "$RESULTS/governors"
cleanup() {
 if [ -n "${SAMPLER:-}" ]; then kill "$SAMPLER" 2>/dev/null || true; fi
 while read -r f governor; do echo "$governor" > "$f"; done < "$RESULTS/governors"
 if [ -n "$APP" ]; then kill -CONT $APP; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$APP" ]; then kill -STOP $APP; fi
unset R36_GAP_POOL
for trial in app1 bench1 bench2 app2; do
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
 while :; do
  hottest=0
  for f in /sys/class/thermal/thermal_zone*/temp; do t=$(cat "$f"); if [ "$t" -gt "$hottest" ]; then hottest=$t; fi; done
  printf '%s,%s\n' "$(date +%s)" "$hottest" >> "$RESULTS/$trial.cooldown"
  if [ "$hottest" -le 50000 ]; then break; fi
  sleep 2
 done
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
 (
  while :; do
   printf 'time=%s\n' "$(date +%s)"
   for f in /sys/class/thermal/thermal_zone*/temp /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; do printf '%s=' "$f"; cat "$f"; done
   sleep 1
  done
 ) > "$RESULTS/$trial.thermal" &
 SAMPLER=$!
 case "$trial" in
  app*) LD_LIBRARY_PATH=/tmp/speedups/base/lib /tmp/app-gap.bin --headless --model /data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf --prompt 'Count from 1 to 100, separated by spaces.' --threads 4 --ctx 2048 --max-tokens 64 --seed 42 --no-prompt-cache > "$RESULTS/$trial.stdout" 2> "$RESULTS/$trial.stderr" ;;
  bench*) LD_LIBRARY_PATH=/tmp/speedups/base/lib /tmp/speedups/base/bin/llama-bench -m /data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf -t 4 -p 0 -n 64 -d 50 -r 1 --no-warmup -lm mmap -ngl 0 -o json > "$RESULTS/$trial.json" 2> "$RESULTS/$trial.stderr" ;;
 esac
 kill "$SAMPLER"; wait "$SAMPLER" 2>/dev/null || true; SAMPLER=
done
sha256sum "$RESULTS"/* > "$RESULTS/SHA256SUMS"
