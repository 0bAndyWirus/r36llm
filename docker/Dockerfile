FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc cpio file rsync unzip wget git libncurses-dev python3 \
    xz-utils patch perl ca-certificates device-tree-compiler u-boot-tools qemu-user \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m br \
    && mkdir /home/br/work && chown br:br /home/br/work
USER br
WORKDIR /src
