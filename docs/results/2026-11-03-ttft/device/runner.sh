#!/bin/sh
set -eu
WORK=/data/r36llm/prompt-cache-measure
ROOT=/data/r36llm
ORIGINAL_PID=${1:-}
APP_PID=
TELEMETRY_PID=
WATCHDOG_PID=
RESUME=0
mkdir -p "$WORK/results"
cp -p "$ROOT/config.ini" "$WORK/config.original"
for marker in loading noautoload; do
 rm -f "$WORK/$marker.original"
 if [ -f "/tmp/r36llm.$marker" ]; then cp -p "/tmp/r36llm.$marker" "$WORK/$marker.original"; fi
done
for p in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
 [ ! -f "$p" ] || printf '%s|%s\n' "$p" "$(cat "$p")"
done > "$WORK/governors.original"
restore() {
 set +e
 [ -z "$WATCHDOG_PID" ] || kill "$WATCHDOG_PID"
 [ -z "$APP_PID" ] || { kill "$APP_PID"; wait "$APP_PID"; }
 [ -z "$TELEMETRY_PID" ] || { kill "$TELEMETRY_PID"; wait "$TELEMETRY_PID"; }
 cp -p "$WORK/config.original" "$ROOT/config.ini"
 while IFS='|' read -r path value; do printf '%s\n' "$value" > "$path"; done < "$WORK/governors.original"
 for marker in loading noautoload; do
  rm -f "/tmp/r36llm.$marker"
  [ ! -f "$WORK/$marker.original" ] || cp -p "$WORK/$marker.original" "/tmp/r36llm.$marker"
 done
 [ "$RESUME" -eq 0 ] || kill -CONT "$ORIGINAL_PID"
 sha256sum "$ROOT/config.ini" > "$WORK/results/restored.sha256"
 cmp "$WORK/config.original" "$ROOT/config.ini" && printf 'config-restored\n' >> "$WORK/results/restored.sha256"
}
trap restore EXIT
trap 'exit 130' HUP INT TERM
(sleep 480; kill -TERM "$$") &
WATCHDOG_PID=$!
if [ -n "$ORIGINAL_PID" ]; then
 read -r pid comm state rest < "/proc/$ORIGINAL_PID/stat"
 case "$state" in T|t) ;; *) kill -STOP "$ORIGINAL_PID"; RESUME=1;; esac
fi
while IFS= read -r line || [ -n "$line" ]; do
 case "$line" in cpu_mode=*|temp=*|top_k=*|top_p=*|output_keep=*) ;; *) printf '%s\n' "$line";; esac
done < "$WORK/config.original" > "$ROOT/config.ini"
printf 'cpu_mode=performance\ntemp=0.5\ntop_k=20\ntop_p=0.9\noutput_keep=\n' >> "$ROOT/config.ini"
sha256sum "$WORK/before" "$WORK/after" "$ROOT/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf" "$ROOT/config.ini" > "$WORK/results/input.sha256"
chmod +x "$WORK/before" "$WORK/after"
governor() {
 for p in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do [ ! -f "$p" ] || printf '%s\n' "$1" > "$p"; done
}
temperature() {
 hottest=0
 for p in /sys/class/thermal/thermal_zone*/temp; do
  value=$(cat "$p")
  [ "$value" -le "$hottest" ] || hottest=$value
 done
 printf '%s\n' "$hottest"
}
cooldown() {
 governor powersave
 count=0
 while [ "$(temperature)" -gt 53000 ]; do
  sleep 2
  count=$((count+1))
  [ "$count" -lt 180 ] || return 1
 done
 governor performance
 [ "$(temperature)" -le 55000 ]
}
run_app() {
 label=$1
 binary=$2
 max_tokens=$3
 printf '%s %s\n' "$(cut -d' ' -f1 /proc/uptime)" "$(temperature)" > "$WORK/results/$label.start"
 "$binary" --headless --model "$ROOT/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf" --prompt 'Count from 1 to 100, separated by spaces.' --threads 4 --ctx 2048 --max-tokens "$max_tokens" --seed 42 > "$WORK/results/$label.out" 2> "$WORK/results/$label.err" &
 APP_PID=$!
 (while kill -0 "$APP_PID" 2>/dev/null; do
  printf '%s,%s' "$(cut -d' ' -f1 /proc/uptime)" "$(temperature)"
  for p in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq /sys/class/thermal/thermal_zone*/temp; do printf ',%s' "$(cat "$p")"; done
  printf '\n'
  sleep 1
 done) > "$WORK/results/$label.thermal.csv" &
 TELEMETRY_PID=$!
 wait "$APP_PID"
 APP_PID=
 kill "$TELEMETRY_PID" 2>/dev/null || true
 wait "$TELEMETRY_PID" 2>/dev/null || true
 TELEMETRY_PID=
}
# Populate any missing persistent prefix before the paired, cooled trials.
run_app prepare "$WORK/before" 1
cooldown
run_app before "$WORK/before" 8
cooldown
run_app after "$WORK/after" 8
