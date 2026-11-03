#!/bin/sh
set -eu
OUT=/data/r36llm/phase-dvfs-2026-11-03
MODEL=/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf
APP_BIN=/tmp/phase-dvfs-r36llm
mkdir -p "$OUT"
[ ! -e "$OUT/original-config.ini" ] || { echo 'Refusing overwrite' >&2; exit 1; }
cp /data/r36llm/config.ini "$OUT/original-config.ini"
APP=$(pidof r36llm.bin || :)
BRIGHTNESS=$(cat /sys/class/backlight/backlight/brightness)
: > "$OUT/limits.tsv"
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
 [ ! -f "$f" ] || printf '%s %s\n' "$f" "$(cat "$f")" >> "$OUT/limits.tsv"
done
SAMPLER=
restore() {
 [ -z "$SAMPLER" ] || kill "$SAMPLER" 2>/dev/null || :
 while read -r path value; do printf '%s\n' "$value" > "$path" || :; done < "$OUT/limits.tsv"
 cp "$OUT/original-config.ini" /data/r36llm/config.ini
 [ -z "$APP" ] || kill -CONT $APP 2>/dev/null || :
 printf '%s\n' "$BRIGHTNESS" > /sys/class/backlight/backlight/brightness
 cmp "$OUT/original-config.ini" /data/r36llm/config.ini
}
trap restore EXIT
trap 'exit 130' INT TERM
[ -z "$APP" ] || kill -STOP $APP
sha256sum /usr/bin/llama-bench "$MODEL" "$APP_BIN" /data/r36llm/config.ini > "$OUT/hashes.txt"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies > "$OUT/frequencies.txt"
echo 0 > /sys/class/backlight/backlight/brightness
cool() {
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
 while :; do
  soc=$(cat /sys/class/thermal/thermal_zone0/temp); gpu=$(cat /sys/class/thermal/thermal_zone1/temp)
  printf '%s,%s,%s\n' "$(date +%s)" "$soc" "$gpu" >> "$OUT/$1-cooldown.csv"
  [ "$soc" -gt 55000 ] || [ "$gpu" -gt 55000 ] || break
  sleep 2
 done
}
for mode in performance phase; do
 # Measure actual headless app TTFT separately, from a cool start.
 cool "$mode-ttft"
 cp "$OUT/original-config.ini" /data/r36llm/config.ini
 printf '\ncpu_mode=%s\n' "$mode" >> /data/r36llm/config.ini
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
 "$APP_BIN" --headless --model "$MODEL" --prompt 'Count from 1 to 100, separated by spaces.' --threads 4 --ctx 2048 --max-tokens 1 --seed 42 --no-prompt-cache > "$OUT/$mode-ttft.out" 2> "$OUT/$mode-ttft.err"
 cool "$mode-sustained"
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
 if [ "$mode" = phase ]; then
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo 1416000 > "$f"; done
 fi
 start=$(date +%s)
 printf 'epoch,elapsed_s,soc_mC,gpu_mC,freq_kHz,scaling_max_kHz,cooling_state\n' > "$OUT/$mode-telemetry.csv"
 sample() {
  now=$(date +%s); state=
  for f in /sys/class/thermal/cooling_device*/cur_state; do [ ! -f "$f" ] || state="${state}$(cat "$f");"; done
  printf '%s,%s,%s,%s,%s,%s,%s\n' "$now" "$((now-start))" "$(cat /sys/class/thermal/thermal_zone0/temp)" "$(cat /sys/class/thermal/thermal_zone1/temp)" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)" "$state"
 }
 (while :; do sample; sleep 2; done) >> "$OUT/$mode-telemetry.csv" & SAMPLER=$!
 trial=0
 while :; do
  trial=$((trial+1))
  /usr/bin/llama-bench -m "$MODEL" -p 0 -n 64 -t 4 -r 1 --no-warmup -o json > "$OUT/$mode-trial$trial.json" 2> "$OUT/$mode-trial$trial.stderr"
  elapsed=$(($(date +%s)-start))
  [ "$trial" -lt 2 ] || [ "$elapsed" -lt 180 ] || break
 done
 sample >> "$OUT/$mode-telemetry.csv"
 kill "$SAMPLER"; wait "$SAMPLER" 2>/dev/null || :; SAMPLER=
 # Undo the cap before the next prompt or cooldown, restoring original limits.
 while read -r path value; do case "$path" in */scaling_max_freq) printf '%s\n' "$value" > "$path";; esac; done < "$OUT/limits.tsv"
done
printf 'complete\n' > "$OUT/status"
