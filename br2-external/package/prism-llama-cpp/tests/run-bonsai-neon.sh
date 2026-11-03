#!/bin/sh
# Usage: sh run-bonsai-neon.sh /path/to/patched/llama.cpp [build-directory]
# Requires aarch64-linux-gnu-gcc and qemu-aarch64 (Debian gcc-aarch64-linux-gnu,
# libc6-dev-arm64-cross, qemu-user). QEMU verifies correctness, not throughput.
# Apply the package patches to the pinned source first. TEST_SOURCE can select
# test-bonsai-rows.c instead of the default single-row correctness harness.
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 PATCHED_LLAMA_SOURCE [BUILD_DIRECTORY]" >&2
    exit 2
fi
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GGML=$(CDPATH= cd -- "$1/ggml" && pwd)
BUILD=${2:-${TMPDIR:-/tmp}/r36-bonsai-neon}
CC=${CC:-aarch64-linux-gnu-gcc}
QEMU=${QEMU:-qemu-aarch64}
SYSROOT=${QEMU_LD_PREFIX:-/usr/aarch64-linux-gnu}
TEST_SOURCE=${TEST_SOURCE:-$HERE/test-bonsai-neon.c}
mkdir -p "$BUILD"
CPUS=$($QEMU -cpu help 2>&1 || true)
case "$CPUS" in
    *cortex-a35*) CPU=cortex-a35 ;;
    *cortex-a53*) CPU=cortex-a53 ;;
    *) echo "QEMU must support cortex-a35 or cortex-a53 (base ARMv8.0)" >&2; exit 1 ;;
esac
printf 'QEMU CPU: %s; compiler: ' "$CPU"
"$CC" --version
# O2/default contraction mirrors the Buildroot optimization level; O3 exercises
# additional optimization with and without FMA contraction. No dotprod/i8mm.
for mode in o2-default o3-no-contract o3-default; do
    case "$mode" in
        o2-default) FLAGS='-O2' ;;
        o3-no-contract) FLAGS='-O3 -ffp-contract=off' ;;
        o3-default) FLAGS='-O3' ;;
    esac
    printf '\nMode: %s (-mcpu=cortex-a35 %s)\n' "$mode" "$FLAGS"
    for source in "$GGML/src/ggml-cpu/quants.c" "$GGML/src/ggml-cpu/arch/arm/quants.c" "$TEST_SOURCE"; do
        case "$source" in
            */arch/arm/*) object=arm.o ;;
            */ggml-cpu/quants.c) object=generic.o ;;
            *) object=test.o ;;
        esac
        # FLAGS is intentionally split into compiler arguments.
        "$CC" -std=c11 -mcpu=cortex-a35 $FLAGS -ffunction-sections -fdata-sections \
            -I"$GGML/include" -I"$GGML/src" -I"$GGML/src/ggml-cpu" -I"$GGML/src/ggml-cpu/arch/arm" \
            -c "$source" -o "$BUILD/$object"
    done
    "$CC" -mcpu=cortex-a35 -Wl,--gc-sections "$BUILD/test.o" "$BUILD/generic.o" "$BUILD/arm.o" -lm -o "$BUILD/test-bonsai-neon-$mode"
    "$QEMU" -L "$SYSROOT" -cpu "$CPU" "$BUILD/test-bonsai-neon-$mode"
done
