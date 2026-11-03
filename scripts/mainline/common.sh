#!/usr/bin/env bash
set -euo pipefail
root=/repo
work=/work
art=$root/out/mainline/artifacts
meta=$root/out/mainline/metadata
mkdir -p "$work" "$art" "$meta" "$root/out/mainline/logs"
export SOURCE_DATE_EPOCH=1793577600
export KBUILD_BUILD_TIMESTAMP='2026-11-02 00:00:00 UTC'
export KBUILD_BUILD_USER=r36llm KBUILD_BUILD_HOST=mainline-build KBUILD_BUILD_VERSION=1
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
fetch_git() {
    local url=$1 commit=$2 dir=$3
    if [[ ! -d $dir/.git ]]; then
        git init "$dir"
        git -C "$dir" fetch --depth=1 "$url" "$commit"
        git -C "$dir" checkout --detach FETCH_HEAD
    fi
    [[ $(git -C "$dir" rev-parse HEAD) == "$commit" ]] || {
        echo "Unexpected source revision in $dir" >&2; return 1;
    }
}
fetch_archr() {
    archr=$work/archr
    fetch_git https://github.com/archr-linux/Arch-R.git \
        6b4904f99bef3fffab490b5ea70ac7de15735885 "$archr"
}
