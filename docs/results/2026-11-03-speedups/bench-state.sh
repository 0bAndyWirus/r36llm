#!/bin/sh
# Run ON THE DEVICE, after other benchmarks have stopped:
#   sh bench-neon.sh /tmp/neon/baseline /tmp/neon/patched
# Each prefix must contain bin/llama-bench and its matching lib/*.so* (or lib64).
# Copy usr/bin/llama-bench and usr/lib/lib{llama,ggml}*.so* from two Buildroot
# builds of pin 5628c7338963b00a598f2a588fd09a79af6d70db: first without, then
# with 0001-arm-neon-armv8.0-bonsai-dot.patch. Use identical build options.
# Rebuild the package from a clean package directory when adding/removing the
# patch; Buildroot's existing .stamp_patched does not detect a new patch file.
# Do not compare a patched executable loading baseline libraries from /usr/lib.
# Keep prefixes in tmpfs/ext4, not FAT/exFAT (shared-library symlinks matter).
# This script pauses the chat app, cools at powersave to <=50 C before each run,
# benchmarks at performance, then restores the original governors and resumes
# the app via an EXIT trap. It does not change config.ini or thermal trip points.
# Override THREADS=4 PROMPT=64 GENERATE=32 REPS=2 ROUNDS=2 COOLDOWN_SECONDS=30
# and START_TEMP_MC=50000. Rounds alternate baseline/patched then patched/baseline.
# Usage: sh bench-neon.sh BASELINE_PREFIX PATCHED_PREFIX [MODEL_DIR [RESULT_DIR]]
# JSON avg_ts is the measured prompt/generation t/s; QEMU timings are not used.
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    echo "usage: $0 BASELINE_PREFIX PATCHED_PREFIX [MODEL_DIR [RESULT_DIR]]" >&2
    exit 2
fi
BASELINE=$(CDPATH= cd -- "$1" && pwd)
PATCHED=$(CDPATH= cd -- "$2" && pwd)
MODELS=${3:-/data/r36llm/models}
RESULTS=${4:-/data/r36llm/bench-neon/$(date +%Y%m%d-%H%M%S)}
THREADS=${THREADS:-4}
PROMPT=${PROMPT:-64}
GENERATE=${GENERATE:-32}
REPS=${REPS:-2}
ROUNDS=${ROUNDS:-2}
COOLDOWN_SECONDS=${COOLDOWN_SECONDS:-30}
START_TEMP_MC=${START_TEMP_MC:-50000}
for value in "$THREADS" "$PROMPT" "$GENERATE" "$REPS" "$ROUNDS" "$COOLDOWN_SECONDS" "$START_TEMP_MC"; do
    case "$value" in ''|*[!0-9]*) echo "Benchmark parameters must be nonnegative integers" >&2; exit 2 ;; esac
done
if [ "$THREADS" -lt 1 ] || [ "$REPS" -lt 1 ] || [ "$ROUNDS" -lt 1 ]; then
    echo "THREADS, REPS and ROUNDS must be positive" >&2; exit 2
fi
if [ "$BASELINE" = "$PATCHED" ]; then
    echo "Baseline and patched prefixes must be different" >&2; exit 2
fi
for prefix in "$BASELINE" "$PATCHED"; do
    test -x "$prefix/bin/llama-bench" || { echo "Missing $prefix/bin/llama-bench" >&2; exit 1; }
    for library in libllama.so libggml.so libggml-base.so libggml-cpu.so; do
        test -r "$prefix/lib/$library" || test -r "$prefix/lib64/$library" || {
            echo "Missing matching $library in $prefix/lib or lib64" >&2; exit 1;
        }
    done
done
for model in Ternary-Bonsai-2-2B-PTQ1_0.gguf; do
    test -r "$MODELS/$model" || { echo "Missing $MODELS/$model" >&2; exit 1; }
done
# Refuse to mix new results with an earlier run.
if [ -e "$RESULTS" ]; then echo "Result path already exists: $RESULTS" >&2; exit 1; fi
mkdir -p "$RESULTS"
APP=$(pidof r36llm r36llm.bin || true)
GOVERNORS="$RESULTS/original-governors.tsv"
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    printf '%s\t%s\n' "$f" "$(cat "$f")"
done > "$GOVERNORS"
SAMPLER=
cleanup() {
    if [ -n "$SAMPLER" ]; then kill "$SAMPLER" 2>/dev/null || true; wait "$SAMPLER" 2>/dev/null || true; fi
    while read -r f governor; do printf '%s\n' "$governor" > "$f"; done < "$GOVERNORS"
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        printf '%s\t%s\n' "$f" "$(cat "$f")"
    done > "$RESULTS/restored-governors.tsv"
    if [ -n "$APP" ]; then kill -CONT $APP 2>/dev/null || true; fi
    echo 'Original CPU governors restored; app resumed.'
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$APP" ]; then kill -STOP $APP; fi
printf '%s\n' "$APP" > "$RESULTS/paused-app-pids.txt"
{
    date -u
    uname -a
    printf 'pin=5628c7338963b00a598f2a588fd09a79af6d70db\nbaseline=%s\npatched=%s\nthreads=%s prompt=%s generate=%s reps=%s rounds=%s cooldown_seconds=%s start_temp_ceiling_mC=%s governor=performance\n' \
        "$BASELINE" "$PATCHED" "$THREADS" "$PROMPT" "$GENERATE" "$REPS" "$ROUNDS" "$COOLDOWN_SECONDS" "$START_TEMP_MC"
    cat /proc/cpuinfo /proc/meminfo /proc/swaps
    for f in /sys/devices/system/cpu/cpu0/cpufreq/*_freq /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor; do
        if [ -r "$f" ]; then printf '%s=' "$f"; cat "$f"; fi
    done
    for prefix in "$BASELINE" "$PATCHED"; do
        sha256sum "$prefix/bin/llama-bench"
        for lib in "$prefix"/lib/libllama*.so* "$prefix"/lib/libggml*.so* "$prefix"/lib64/libllama*.so* "$prefix"/lib64/libggml*.so*; do
            if [ -f "$lib" ]; then sha256sum "$lib"; fi
        done
    done
} > "$RESULTS/metadata.txt"
round=1
while [ "$round" -le "$ROUNDS" ]; do
    if [ $((round % 2)) -eq 1 ]; then order='baseline patched'; else order='patched baseline'; fi
    for model in Ternary-Bonsai-2-2B-PTQ1_0.gguf; do
        for variant in $order; do
            if [ -e /tmp/speedups-hand-back ]; then
                echo 'Hand-back requested; stopping before the next run.'
                exit 0
            fi
            case "$variant" in baseline) prefix=$BASELINE; export GGML_GDN_STATE_GATHER=1 ;; patched) prefix=$PATCHED; unset GGML_GDN_STATE_GATHER ;; esac
            stem="$RESULTS/round-$round-$variant-${model%.gguf}"
            printf 'round=%s variant=%s model=%s cooldown=%ss\n' "$round" "$variant" "$model" "$COOLDOWN_SECONDS"
            for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
            sleep "$COOLDOWN_SECONDS"
            while :; do
                hottest=0
                for f in /sys/class/thermal/thermal_zone*/temp; do
                    temp=$(cat "$f")
                    if [ "$temp" -gt "$hottest" ]; then hottest=$temp; fi
                done
                printf 'time=%s hottest_mC=%s\n' "$(date +%s)" "$hottest" >> "$stem.cooldown"
                if [ "$hottest" -le "$START_TEMP_MC" ]; then break; fi
                sleep 2
            done
            for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
            cat /proc/meminfo > "$stem.meminfo"
            (
                while :; do
                    printf 'time=%s\n' "$(date +%s)"
                    for f in /sys/class/thermal/thermal_zone*/temp /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; do
                        if [ -r "$f" ]; then printf '%s=' "$f"; cat "$f"; fi
                    done
                    sleep 1
                done
            ) > "$stem.thermal" &
            SAMPLER=$!
            status=0
            LD_LIBRARY_PATH="$prefix/lib:$prefix/lib64" "$prefix/bin/llama-bench" \
                -m "$MODELS/$model" -t "$THREADS" -p "$PROMPT" -n "$GENERATE" -r "$REPS" -o json \
                > "$stem.json" 2> "$stem.stderr" || status=$?
            kill "$SAMPLER" 2>/dev/null || true
            wait "$SAMPLER" 2>/dev/null || true
            SAMPLER=
            if [ "$status" -ne 0 ]; then
                echo "llama-bench failed ($status); see $stem.stderr" >&2
                exit "$status"
            fi
        done
    done
    round=$((round + 1))
done
printf 'Results: %s (compare JSON avg_ts for matching model, n_prompt and n_gen)\n' "$RESULTS"
