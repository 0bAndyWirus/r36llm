# Contributing

Read the [README](README.md) for build and device instructions. On Windows, run `scripts/build.ps1` with Docker Desktop using Linux containers; Linux hosts can use the Docker shell entry points described there. Use `scripts/build.ps1 -Release` for a distributable image.

Follow `app/.clang-format` for application code. CI builds the app natively against the pinned, patched PrismML engine, runs ShellCheck at error severity and Python syntax checks, and checks NEON results under QEMU Cortex-A35. See [CI](.github/workflows/ci.yml) for details.

To propose support for a new board, open the board report issue form and include its PCB marking, stock OS, DTB name, and test results. Do not commit harvested vendor binaries in pull requests.

Use a short commit subject in the existing `area: description` style, for example `app: fix gamepad input`.
