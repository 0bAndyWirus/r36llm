# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Source-built Linux 4.4 kernel, U-Boot, and image build pipeline. The resulting image still needs a hardware boot test.
- Opt-in Linux 6.12.114/Arch R image build with mainline U-Boot, Panel 8 overlay, matching joypad module, and offline image checks. Hardware boot is untested; the optional DWC2 host overlay is experimental.
- FAT32 data partition with first-boot growth on fresh images; hardware verification is pending. Release images contain no model or personal SSH authorization key. The separately downloaded default is PrismML's Apache-2.0 Ternary-Bonsai-2-2B, based on Qwen/Qwen3.5-2B.
- ARMv8.0 NEON Bonsai dot-product paths for the pinned PrismML fork, with GCC 12.2/Buildroot 13.4 bit-exact Cortex-A35 checks. The two-row `0002` patch improves default PTQ1_0 decode by 20.2% and 1.7B PQ2_0 by 12.8% over `0001` in controlled AB/BA trials; [method and evidence](docs/results/2026-11-03-speedups/method.txt).
- Optional English/French output-head restriction for the default PTQ1_0 model, enabled with `output_keep` in `config.ini`. The full input vocabulary stays intact; the full output head remains the default. Native x86 checks found bit-identical kept logits and unchanged greedy output on four EN/FR prompts.
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
