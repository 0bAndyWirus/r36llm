#!/bin/sh
# Run ON DEVICE only after the orchestrator releases it. Never changes libs/config.
# Usage: sh bench-device.sh ISOLATED_PREFIX KEEP_LIST [MODEL [NEW_RESULTS_DIR]]
# Four matched runs: full/restricted, restricted/full; four threads, <=55 C.
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    echo "usage: $0 PREFIX KEEP_LIST [MODEL [NEW_RESULTS_DIR]]" >&2
    exit 2
fi
PREFIX=$(CDPATH= cd -- "$1" && pwd)
KEEP=$2
MODEL=${3:-/data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf}
RESULTS=${4:-/data/r36llm/bench-vocab/$(date +%Y%m%d-%H%M%S)}
START_TEMP_MC=${START_TEMP_MC:-55000}
COOLDOWN_SECONDS=${COOLDOWN_SECONDS:-30}
GENERATE=${GENERATE:-128}
for value in "$START_TEMP_MC" "$COOLDOWN_SECONDS" "$GENERATE"; do
    case "$value" in ''|*[!0-9]*) echo 'Parameters must be nonnegative integers' >&2; exit 2 ;; esac
done
if [ "$START_TEMP_MC" -gt 55000 ] || [ "$GENERATE" -lt 1 ]; then
    echo 'Start temperature must be <=55000 mC; generation must be positive' >&2
    exit 2
fi
test -x "$PREFIX/bin/llama-bench"
test -r "$KEEP"
test -r "$MODEL"
if [ -e "$RESULTS" ]; then echo "Refusing existing results: $RESULTS" >&2; exit 1; fi
mkdir -p "$RESULTS"
APP=$(pidof r36llm || true)
GOVERNORS="$RESULTS/original-governors.tsv"
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    printf '%s\t%s\n' "$f" "$(cat "$f")"
done > "$GOVERNORS"
SAMPLER=
BENCH=
cleanup() {
    if [ -n "$BENCH" ]; then kill "$BENCH" 2>/dev/null || true; wait "$BENCH" 2>/dev/null || true; fi
    if [ -n "$SAMPLER" ]; then kill "$SAMPLER" 2>/dev/null || true; wait "$SAMPLER" 2>/dev/null || true; fi
    while read -r f governor; do printf '%s\n' "$governor" > "$f"; done < "$GOVERNORS"
    if [ -n "$APP" ]; then kill -CONT $APP 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ -n "$APP" ]; then kill -STOP $APP; fi
{
    date -u
    uname -a
    printf 'pin=5628c7338963b00a598f2a588fd09a79af6d70db\nprefix=%s\nmodel=%s\nkeep=%s\nthreads=4\nprompt=64\ngenerate=%s\nrounds=2\nstart_ceiling_mC=%s\n' "$PREFIX" "$MODEL" "$KEEP" "$GENERATE" "$START_TEMP_MC"
    sha256sum "$PREFIX/bin/llama-bench" "$PREFIX"/lib/*.so* "$KEEP"
    cat /proc/meminfo
} > "$RESULTS/metadata.txt"
for round in 1 2; do
    if [ "$round" = 1 ]; then order='full restricted'; else order='restricted full'; fi
    for variant in $order; do
        stem="$RESULTS/round-$round-$variant"
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$f"; done
        sleep "$COOLDOWN_SECONDS"
        while :; do
            hottest=0
            for f in /sys/class/thermal/thermal_zone*/temp; do
                temp=$(cat "$f")
                if [ "$temp" -gt "$hottest" ]; then hottest=$temp; fi
            done
            printf '%s\t%s\n' "$(date +%s)" "$hottest" >> "$stem.cooldown.tsv"
            if [ "$hottest" -le "$START_TEMP_MC" ]; then break; fi
            sleep 2
        done
        printf '%s\n' "$hottest" > "$stem.start-temp-mC"
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done
        if [ "$variant" = restricted ]; then export LLAMA_OUTPUT_KEEP="$KEEP"; else unset LLAMA_OUTPUT_KEEP; fi
        LD_LIBRARY_PATH="$PREFIX/lib" "$PREFIX/bin/llama-bench" \
            -m "$MODEL" -ngl 0 -t 4 -p 64 -n "$GENERATE" -r 1 -o json \
            > "$stem.json" 2> "$stem.stderr" &
        BENCH=$!
        (
            while kill -0 "$BENCH" 2>/dev/null; do
                printf 'time=%s\n' "$(date +%s)"
                if [ -r "/proc/$BENCH/status" ]; then cat "/proc/$BENCH/status"; fi
                for f in /sys/class/thermal/thermal_zone*/temp; do printf '%s=' "$f"; cat "$f"; done
                sleep 0.2
            done
        ) > "$stem.resources" &
        SAMPLER=$!
        status=0
        wait "$BENCH" || status=$?
        BENCH=
        kill "$SAMPLER" 2>/dev/null || true
        wait "$SAMPLER" 2>/dev/null || true
        SAMPLER=
        if [ "$status" -ne 0 ]; then echo "Benchmark failed: $stem" >&2; exit "$status"; fi
        printf 'Completed round=%s variant=%s start_mC=%s\n' "$round" "$variant" "$hottest"
    done
done
unset LLAMA_OUTPUT_KEEP
printf 'Results: %s\n' "$RESULTS"
