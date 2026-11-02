#!/bin/sh
set -eu
WORK=/home/br/work
VERSION=2025.02.19
if [ ! -d "$WORK/buildroot-$VERSION" ]; then
    wget -O "$WORK/buildroot-$VERSION.tar.xz" "https://buildroot.org/downloads/buildroot-$VERSION.tar.xz"
    tar -xJf "$WORK/buildroot-$VERSION.tar.xz" -C "$WORK"
fi
exec make -C "$WORK/buildroot-$VERSION" O="$WORK/output" BR2_EXTERNAL=/src/br2-external "$@"
