#!/bin/sh
set -eu
OUT=/data/r36llm/profile-2026-11-02
TOOLS="$OUT/tools"
mkdir -p "$OUT"
[ ! -e "$OUT/original-governors.tsv" ] || { echo 'Refusing to overwrite original state'; exit 1; }
APP=$(pidof r36llm || :)
: > "$OUT/original-governors.tsv"
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
 printf '%s\t%s\n' "$f" "$(cat "$f")" >> "$OUT/original-governors.tsv"
done
sha256sum /data/r36llm/config.ini > "$OUT/original-config.sha256"
SAMPLER=
restore() {
 [ -z "$SAMPLER" ] || kill "$SAMPLER" 2>/dev/null || :
 while read -r f governor; do printf '%s\n' "$governor" > "$f"; done < "$OUT/original-governors.tsv"
 [ -z "$APP" ] || kill -CONT $APP 2>/dev/null || :
 sha256sum -c "$OUT/original-config.sha256"
 while read -r f governor; do [ "$(cat "$f")" = "$governor" ]; done < "$OUT/original-governors.tsv"
 echo 'Original CPU governors restored; config unchanged; app resumed.'
 [ -z "$APP" ] || cat /proc/$APP/status
}
trap restore EXIT
trap 'exit 130' INT TERM
[ -z "$APP" ] || kill -STOP $APP
{
 date -u; uname -a; cat /proc/meminfo; command -v perf || :
 sha256sum "$TOOLS/bin/"* "$TOOLS/lib/"*.so* /usr/bin/llama-bench /data/r36llm/models/Ternary-Bonsai-*.gguf
 cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
} > "$OUT/device.txt" 2>&1
export LD_LIBRARY_PATH="$TOOLS/lib"
printf 'run,start_soc_mC,start_gpu_mC,end_soc_mC,end_gpu_mC\n' > "$OUT/runs.csv"
cool() {
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
 printf 'epoch,soc_mC,gpu_mC\n' > "$OUT/$NAME-cooldown.csv"
 while :; do
  soc=$(cat /sys/class/thermal/thermal_zone0/temp); gpu=$(cat /sys/class/thermal/thermal_zone1/temp)
  printf '%s,%s,%s\n' "$(date +%s)" "$soc" "$gpu" >> "$OUT/$NAME-cooldown.csv"
  [ "$soc" -gt 55000 ] || [ "$gpu" -gt 55000 ] || break
  sleep 2
 done
 for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
}
sample() {
 state=
 for f in /sys/class/thermal/cooling_device*/cur_state; do state="${state}$(cat "$f");"; done
 printf '%s,%s,%s,%s,%s\n' "$(date +%s)" "$(cat /sys/class/thermal/thermal_zone0/temp)" "$(cat /sys/class/thermal/thermal_zone1/temp)" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)" "$state"
}
for model in Ternary-Bonsai-2-2B-PTQ1_0 Ternary-Bonsai-1.7B-PQ2_0; do
 for mode in plain profile bench; do
  NAME="$model-$mode"
  cool
  start_soc=$(cat /sys/class/thermal/thermal_zone0/temp); start_gpu=$(cat /sys/class/thermal/thermal_zone1/temp)
  printf 'epoch,soc_mC,gpu_mC,freq_kHz,cooling_states\n' > "$OUT/$NAME-telemetry.csv"
  (while :; do sample; sleep 2; done) >> "$OUT/$NAME-telemetry.csv" &
  SAMPLER=$!
  echo "$(date -u) $NAME"
  if [ "$mode" = bench ]; then
   "$TOOLS/bin/llama-bench" -m "/data/r36llm/models/$model.gguf" -p 8 -n 8 -t 4 -r 3 -o json > "$OUT/$NAME.json" 2> "$OUT/$NAME.stderr"
  else
   "$TOOLS/bin/profile" "/data/r36llm/models/$model.gguf" "$OUT/$NAME" "$mode" > "$OUT/$NAME.stdout" 2> "$OUT/$NAME.stderr"
  fi
  sample >> "$OUT/$NAME-telemetry.csv"
  kill "$SAMPLER"; wait "$SAMPLER" 2>/dev/null || :; SAMPLER=
  printf '%s,%s,%s,%s,%s\n' "$NAME" "$start_soc" "$start_gpu" "$(cat /sys/class/thermal/thermal_zone0/temp)" "$(cat /sys/class/thermal/thermal_zone1/temp)" >> "$OUT/runs.csv"
 done
done
restore
trap - EXIT
printf 'complete\n' > "$OUT/status"
echo PROFILE_COMPLETE
