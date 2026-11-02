#!/bin/sh
# Run on the device as root. All outputs stay on /data; no boot files are changed.
set -eu
OUT=/data/r36llm/thermal-2026-11-02
MODEL=/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf
mkdir -p "$OUT"
[ ! -e "$OUT/original-config.ini" ] || { echo 'Refusing to overwrite original config'; exit 1; }
cp /data/r36llm/config.ini "$OUT/original-config.ini"
APP=$(pidof r36llm || :)
: > "$OUT/original-governors.tsv"
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    printf '%s\t%s\n' "$f" "$(cat "$f")" >> "$OUT/original-governors.tsv"
done
SAMPLER=
restore() {
    [ -z "$SAMPLER" ] || kill "$SAMPLER" 2>/dev/null || :
    cp "$OUT/original-config.ini" /data/r36llm/config.ini
    while read -r f governor; do printf '%s\n' "$governor" > "$f"; done < "$OUT/original-governors.tsv"
    [ -z "$APP" ] || kill -CONT $APP 2>/dev/null || :
    cmp "$OUT/original-config.ini" /data/r36llm/config.ini
    echo 'Original config restored byte-for-byte; original CPU governors restored; app resumed.'
}
trap restore EXIT
trap 'exit 130' INT TERM
[ -z "$APP" ] || kill -STOP $APP
{
    date -u
    uname -a
    cat /proc/meminfo
    cat /proc/swaps
    sha256sum /usr/bin/llama-bench "$MODEL" /data/r36llm/config.ini
    /usr/bin/llama-bench --version
    cat /etc/init.d/S05perf
    for f in /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/trip_point_* /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors /sys/class/backlight/*/brightness; do
        [ ! -f "$f" ] || { echo "$f"; cat "$f"; }
    done
} > "$OUT/device.txt" 2>&1
printf 'cpu_mode,threads,governor,start_soc_mC,start_gpu_mC,start_epoch,end_epoch,trials,final_freq_kHz,final_cooling_state\n' > "$OUT/runs.csv"
echo SWEEP_READY
for mode in performance balanced saver; do
    case "$mode" in performance) governor=performance;; balanced) governor=ondemand;; saver) governor=powersave;; esac
    for threads in 2 3 4; do
        name="$mode-t$threads"
        # Cool at the minimum frequency; use the same <=55 C ceiling for every run.
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
        printf 'epoch,soc_mC,gpu_mC\n' > "$OUT/$name-cooldown.csv"
        while :; do
            soc=$(cat /sys/class/thermal/thermal_zone0/temp)
            gpu=$(cat /sys/class/thermal/thermal_zone1/temp)
            printf '%s,%s,%s\n' "$(date +%s)" "$soc" "$gpu" >> "$OUT/$name-cooldown.csv"
            [ "$soc" -gt 55000 ] || [ "$gpu" -gt 55000 ] || break
            sleep 2
        done
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "$governor" > "$f"; done
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ "$(cat "$f")" = "$governor" ] || exit 1
        done
        start_soc=$(cat /sys/class/thermal/thermal_zone0/temp)
        start_gpu=$(cat /sys/class/thermal/thermal_zone1/temp)
        start=$(date +%s)
        printf 'epoch,elapsed_s,soc_mC,gpu_mC,freq_kHz,scaling_max_kHz,cooling_state\n' > "$OUT/$name-telemetry.csv"
        sample() {
            now=$(date +%s)
            state=
            for f in /sys/class/thermal/cooling_device*/cur_state; do
                [ ! -f "$f" ] || state="${state}$(cat "$f");"
            done
            printf '%s,%s,%s,%s,%s,%s,%s\n' "$now" "$((now-start))" "$(cat /sys/class/thermal/thermal_zone0/temp)" "$(cat /sys/class/thermal/thermal_zone1/temp)" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq)" "$state"
        }
        (while :; do sample; sleep 2; done) >> "$OUT/$name-telemetry.csv" &
        SAMPLER=$!
        trial=0
        # Two back-to-back tg64 trials, extending to >=180 s if needed.
        # Separate JSON files retain each trial's raw timing rather than an aggregate only.
        while :; do
            trial=$((trial+1))
            echo "$(date -u) $name trial=$trial"
            /usr/bin/llama-bench -m "$MODEL" -p 0 -n 64 -t "$threads" -r 1 --no-warmup -o json > "$OUT/$name-trial$trial.json" 2> "$OUT/$name-trial$trial.stderr"
            elapsed=$(($(date +%s)-start))
            [ "$trial" -lt 2 ] || [ "$elapsed" -lt 180 ] || break
        done
        sample >> "$OUT/$name-telemetry.csv"
        end=$(date +%s)
        final_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
        final_state=
        for f in /sys/class/thermal/cooling_device*/cur_state; do
            [ ! -f "$f" ] || final_state="${final_state}$(cat "$f");"
        done
        kill "$SAMPLER"
        wait "$SAMPLER" 2>/dev/null || :
        SAMPLER=
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$mode" "$threads" "$governor" "$start_soc" "$start_gpu" "$start" "$end" "$trial" "$final_freq" "$final_state" >> "$OUT/runs.csv"
    done
done
restore
trap - EXIT
printf 'complete\n' > "$OUT/status"
echo SWEEP_COMPLETE
