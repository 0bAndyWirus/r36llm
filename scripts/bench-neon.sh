#!/bin/sh
# Run ON THE DEVICE, after other benchmarks have stopped:
#   sh bench-neon.sh /data/neon/baseline /data/neon/patched
# Each prefix must contain bin/llama-bench and its matching lib/*.so* (or lib64).
# Copy usr/bin/llama-bench and usr/lib/lib{llama,ggml}*.so* from two Buildroot
# builds of pin 5628c7338963b00a598f2a588fd09a79af6d70db: first without, then
# with 0001-arm-neon-armv8.0-bonsai-dot.patch. Use identical build options.
# Rebuild the package from a clean package directory when adding/removing the
# patch; Buildroot's existing .stamp_patched does not detect a new patch file.
# Do not compare a patched executable loading baseline libraries from /usr/lib.
# This script stops the chat app and prevents model auto-load during the run.
# It does not change CPU/thermal settings: choose the same CPU mode beforehand.
# Override THREADS=4 PROMPT=64 GENERATE=32 REPS=2 ROUNDS=2 COOLDOWN_SECONDS=30.
# Rounds alternate baseline/patched and patched/baseline to expose order bias.
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
for value in "$THREADS" "$PROMPT" "$GENERATE" "$REPS" "$ROUNDS" "$COOLDOWN_SECONDS"; do
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
for model in Bonsai-1.7B-Q1_0.gguf Ternary-Bonsai-1.7B-PQ2_0.gguf Ternary-Bonsai-2-2B-PTQ1_0.gguf; do
    test -r "$MODELS/$model" || { echo "Missing $MODELS/$model" >&2; exit 1; }
done
# Refuse to mix new results with an earlier run.
if [ -e "$RESULTS" ]; then echo "Result path already exists: $RESULTS" >&2; exit 1; fi
mkdir -p "$RESULTS"
GUARD=/tmp/r36llm.noautoload
CREATED_GUARD=0
SAMPLER=
cleanup() {
    if [ -n "$SAMPLER" ]; then kill "$SAMPLER" 2>/dev/null || true; wait "$SAMPLER" 2>/dev/null || true; fi
    if [ "$CREATED_GUARD" = 1 ]; then rm -f "$GUARD"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ ! -e "$GUARD" ]; then touch "$GUARD"; CREATED_GUARD=1; fi
killall r36llm 2>/dev/null || true
sleep 2
{
    date -u
    uname -a
    printf 'pin=5628c7338963b00a598f2a588fd09a79af6d70db\nbaseline=%s\npatched=%s\nthreads=%s prompt=%s generate=%s reps=%s rounds=%s cooldown_seconds=%s\n' \
        "$BASELINE" "$PATCHED" "$THREADS" "$PROMPT" "$GENERATE" "$REPS" "$ROUNDS" "$COOLDOWN_SECONDS"
    cat /proc/cpuinfo /proc/meminfo /proc/swaps
    for f in /sys/devices/system/cpu/cpufreq/policy*/*_freq /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
        if [ -r "$f" ]; then printf '%s=' "$f"; cat "$f"; fi
    done
    for prefix in "$BASELINE" "$PATCHED"; do
        sha256sum "$prefix/bin/llama-bench"
        for lib in "$prefix"/lib/libllama.so* "$prefix"/lib/libggml*.so* "$prefix"/lib64/libllama.so* "$prefix"/lib64/libggml*.so*; do
            if [ -f "$lib" ]; then sha256sum "$lib"; fi
        done
    done
} > "$RESULTS/metadata.txt"
round=1
while [ "$round" -le "$ROUNDS" ]; do
    if [ $((round % 2)) -eq 1 ]; then order='baseline patched'; else order='patched baseline'; fi
    for model in Bonsai-1.7B-Q1_0.gguf Ternary-Bonsai-1.7B-PQ2_0.gguf Ternary-Bonsai-2-2B-PTQ1_0.gguf; do
        for variant in $order; do
            case "$variant" in baseline) prefix=$BASELINE ;; patched) prefix=$PATCHED ;; esac
            stem="$RESULTS/round-$round-$variant-${model%.gguf}"
            printf 'round=%s variant=%s model=%s cooldown=%ss\n' "$round" "$variant" "$model" "$COOLDOWN_SECONDS"
            sleep "$COOLDOWN_SECONDS"
            cat /proc/meminfo > "$stem.meminfo"
            (
                while :; do
                    printf 'time=%s\n' "$(date +%s)"
                    for f in /sys/class/thermal/thermal_zone*/temp /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq; do
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
