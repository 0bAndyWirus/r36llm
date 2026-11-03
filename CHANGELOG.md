# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Source-built Linux 4.4 kernel, U-Boot, and image build pipeline. The resulting image still needs a hardware boot test.
- FAT32 data partition with first-boot growth on fresh images; hardware verification is pending. Release images contain no model or personal SSH authorization key.
- ARMv8.0 NEON Bonsai dot-product paths for the pinned PrismML fork. Bit-identical results were checked under QEMU; on-device speed measurements are pending.
- CI for native application builds, shell and Python checks, and Cortex-A35 NEON correctness; release workflow for image and source artifacts; Dependabot for GitHub Actions.
- README SSH instructions that retain host-key checking and use a dedicated known-hosts file.

### Fixed

- Release legal-info collection for the Linux 4.4 kernel headers.

## Initial public state — 2026-11-02

Commit `d4ef376` established the initial repository state; it was not a tagged release.

### Added

- Buildroot initramfs and framebuffer gamepad chat application using the pinned PrismML llama.cpp fork, tested on the G80CA-MB V1.3 Panel 8 board with its vendor kernel.
- USB-Ethernet SSH access, model selection, chat logging, device settings, power controls, and temperature and battery status.
- Build, deployment, model download, benchmark, and screenshot tools, plus device benchmarks and screenshots.
- Documentation and MIT license. Vendor kernel binaries and personal keys are kept out of the repository.

### Known limitations

- USB gadget mode did not work on the tested vendor kernel; USB Ethernet was used instead.
- Inference is slow and sustained workloads can reach thermal throttling temperatures.
