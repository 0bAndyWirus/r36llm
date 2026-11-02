# Benchmarks

R36S clone (RK3326, 4x Cortex-A35 @ 1512 MHz, NEON only, no dotprod), 895 MB RAM, 10858 MB swap, Linux 4.4.189, governor `performance`.
Engine: PrismML llama.cpp fork, CPU only, 4 threads. `llama-bench -p 64 -n 32 -r 2`. Measured 2026-11-02.

|Model|File MB|RAM free before (MB)|Prompt t/s|Generation t/s|Words/min|100-token answer|Peak temp|Fits|
|---|---:|---:|---:|---:|---:|---:|---:|---|
|Bonsai-1.7B-Q1_0|237|829|1.26|0.82|37|121 s|85 °C|yes|
|Bonsai-4B-Q1_0|546|830|0.48|0.38|17|265 s|84 °C|yes|
|SmolLM2-135M-Instruct-Q4_0|88|829|17.98|10.13|456|10 s|82 °C|yes|
|Ternary-Bonsai-1.7B-PQ2_0|442|829|1.52|1.01|45|99 s|83 °C|yes|
|Ternary-Bonsai-2-2B-PTQ1_0|409|829|1.13|0.68|31|147 s|83 °C|yes|

Words/min assumes ~0.75 English words per token. "Fits" means generation stays above 0.3 t/s (no swap thrashing). Peak temp is the hottest thermal zone sampled once per second during the run (passive cooling, no fan).
Raw data: [results/2026-11-02/bench.json](results/2026-11-02/bench.json).

## Sustained performance

Measured 2026-11-02 on the default `Ternary-Bonsai-2-2B-PTQ1_0.gguf`, using the installed PrismML CPU benchmark (GNU 13.4.0, version `0.7.0-dev`, build/commit unknown). Binary and model SHA-256 hashes are recorded in [device.txt](results/2026-11-02-thermal/device.txt); these results describe that binary, not later kernel optimizations.

Each setting ran back-to-back `llama-bench -m /data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf -p 0 -n 64 -t N -r 1 --no-warmup -o json` trials for at least 180 seconds, with at least two trials. This tests repeated short-context generation, not one 512-token answer. The app was suspended and the screen backlight was off. Both thermal zones, CPU frequency, maximum frequency and all thermal cooling-device states were sampled every 2 seconds.

Before each setting, the CPU used `powersave` until both thermal zones read at most 55 °C. Start temperature below is the hotter zone reread after applying the selected governor; it reached 56.8 °C during that transition. `performance`, `balanced` and `saver` map to the CPU governors `performance`, `ondemand` and `powersave`. The app applies these through `apply_cpu_mode`; `r36-config` only reads settings. The measured device's `S05perf` sets CPU and devfreq governors to `performance` at boot. This sweep changed only CPU governors, leaving devfreq governors unchanged.

|CPU mode|Threads|Run s|Start °C|Avg t/s|First / last tg64 t/s|Peak °C|Final MHz|Throttling|
|---|---:|---:|---:|---:|---:|---:|---:|---|
|performance|2|257|53.3|0.513|0.513 / 0.512|73.8|1512|no|
|performance|3|181|55.0|0.737|0.748 / 0.728|84.2|1512|yes|
|performance|4|238|55.9|0.843|0.868 / 0.828|82.7|1512|yes|
|balanced|2|258|55.9|0.511|0.511 / 0.512|79.2|1416|no|
|balanced|3|185|55.5|0.719|0.731 / 0.708|84.2|1416|yes|
|balanced|4|242|56.8|0.829|0.856 / 0.815|82.7|1512|yes|
|saver|2|327|56.4|0.402|0.398 / 0.406|64.6|1008|no|
|saver|3|225|54.2|0.590|0.594 / 0.587|68.1|1008|no|
|saver|4|216|55.9|0.615|0.525 / 0.744|72.5|1008|no|

Average throughput is total generated tokens divided by total timed generation seconds, excluding model loading and sampling overhead outside the timed generation. Run seconds include those gaps. First and last are separate 64-token trials, not windows within a single answer. Peak is the hottest sampled zone. Final frequency is read after the benchmark process exits, so it can recover before that reading: the throttled rows reached 1008 MHz under load, CPU cooling state 5 and devfreq cooling state 2. No thermal cooling activated in the other rows; `saver`'s fixed 1008 MHz is governor policy, not throttling.

**Keep the defaults `cpu_mode=performance`, `threads=4`.** They produced the highest average throughput (0.843 t/s) and highest final-trial throughput (0.828 t/s), despite throttling and a 4.7% first-to-last slowdown. `balanced` with 4 threads had the same sampled peak temperature and slightly lower throughput, so it offers no measured temperature-headroom tie-break. For lower temperatures, `saver` with 4 threads averaged 0.615 t/s at a 72.5 °C peak, without thermal cooling.

This was one ordered sweep, not randomized repeated sessions; small differences need that context. The `saver`/4 first-to-last increase occurred without recorded thermal cooling, and its cause was not established. The original device `config.ini` was restored byte-for-byte, the original CPU governors were restored and the app was resumed before releasing the device.

Raw data and the on-device runner: [results/2026-11-02-thermal/](results/2026-11-02-thermal/). The [summary CSV](results/2026-11-02-thermal/summary.csv) includes all nine settings; per-trial JSON/stderr, 2-second telemetry and cooldown CSVs, original settings and the restoration log are retained alongside it.

## App overhead

The app now prepares the ChatML system prefix on its existing loading worker, while
the UI remains busy. New chats restore sequence 0 with the pinned fork's
`llama_state_seq_get_size`, `llama_state_seq_get_data` and
`llama_state_seq_set_data` APIs. The in-memory snapshot excludes the sampler; each
answer starts a fresh sampler with the requested seed.

Persistent snapshots live at `/data/r36llm/cache/<key>.kv`. The key includes the
model path, file size and nanosecond modification time, system prompt, requested
context size, thinking-template flag and engine identity. Engine identity includes
the installed library's SHA-256 digest because archive builds can report an unknown
commit. The envelope checks its version, key, token count, payload size and payload
checksum before passing bytes to llama. This checksum detects corruption; it does
not authenticate files against a malicious writer. Writes use a flushed and synced
temporary file followed by rename. On filesystems that reject rename-over, removing
the old file before rename can lose a cache after interruption, but cannot publish
a partial snapshot.

Previously, the UI drew and converted all 640 × 480 framebuffer pixels after every
30 ms input poll, even when nothing changed. It now redraws on input and visible
state changes, samples streaming changes at most every 100 ms, and retains
one-second device-stat refreshes. Input still blocks in `poll`; no CPU affinity or
thread-priority changes were made.

Headless measurement controls are `--seed N`, `--repeat N` (a fresh chat after each
answer) and `--no-prompt-cache`. Standard error reports model-load time and
per-answer time to the first published token, generated-token count and unrounded
generation throughput. Load time includes prefix preparation on a cache miss;
answer TTFT starts after the loaded/busy transition, not at process launch.

### Native cache checks

An Ubuntu 24.04 Docker container built the pinned engine
`5628c7338963b00a598f2a588fd09a79af6d70db` with the CI patch and the exact
`.github/workflows/ci.yml` app-job flags. The app configured with
`-DR36LLM_BUILD_TESTS=ON`, built successfully, and `ctest --output-on-failure`
passed all four suites: `config`, `chat_text`, `keymap` and `prompt_cache`.
CTest sets the installed engine library directory for its transitive shared
dependencies; an initial run without this setting could not load `libggml.so.0`.

With the default 2B model, prompt `Say hello.`, seed 42, four threads, context 2048
and at most 32 tokens, all five answers matched byte-for-byte after excluding only
the throughput lines: no cache, cold cache, persisted cache, and two fresh chats
in one process. Each answer was `Hello! I'm ready to help.` followed by a newline.
Logs confirmed preparation on the cold load and a disk hit on the next process.
Flipping a snapshot byte and truncating a snapshot to 64 bytes each caused a
recompute, not a hit, with the same answer. Sending SIGTERM during a long
system-prefix evaluation stopped computation and published no cache file.

The headless command was:

```sh
r36llm --headless --model /data/r36llm/models/Ternary-Bonsai-2-2B-PTQ1_0.gguf \
  --prompt 'Say hello.' --threads 4 --ctx 2048 --max-tokens 32 --seed 42
```

The native run used `/src/models/` instead of `/data/r36llm/models/` and
`LD_LIBRARY_PATH=/tmp/llama-install/lib`. Variants added `--no-prompt-cache` or
`--repeat 2`. These are correctness checks, not device performance measurements.

## NEON ARMv8.0 Bonsai patch

Measured 2026-11-02 on the device, comparing clean PrismML pin
`5628c7338963b00a598f2a588fd09a79af6d70db` with the same pin plus
[`0001-arm-neon-armv8.0-bonsai-dot.patch`](../br2-external/package/prism-llama-cpp/0001-arm-neon-armv8.0-bonsai-dot.patch).
Both variants used Buildroot GCC 13.4.0, the image package's CMake options,
`-O2 -march=armv8-a`, OpenMP and four threads. Each executable loaded its own
matching shared libraries from a separate tmpfs prefix; `/data` is exFAT and
cannot preserve the library symlinks. The clean pin already has NEON fallbacks:
this patch specializes them, rather than replacing wholly scalar execution.

The [runner](../scripts/bench-neon.sh) used `-p 64 -n 32 -r 2` in two rounds:
baseline/patched, then patched/baseline for each model. Before every run it
cooled at `powersave` until the hottest thermal zone was at most 50 °C, then
selected `performance`. Recorded cooldown endpoints were 48.6–50.0 °C.
The chat app was paused throughout. Each table value is the arithmetic mean
of four timed samples, matching `llama-bench`'s `avg_ts` convention.

|Model|Baseline prompt t/s|Patched prompt t/s|Prompt speedup|Baseline generation t/s|Patched generation t/s|Generation speedup|
|---|---:|---:|---:|---:|---:|---:|
|Bonsai-1.7B Q1_0|1.426|2.041|1.43×|1.040|1.459|1.40×|
|Ternary-Bonsai-1.7B PQ2_0|1.762|1.973|1.12×|1.258|1.396|1.11×|
|Ternary-Bonsai-2-2B PTQ1_0|1.291|1.449|1.12×|0.826|0.918|1.11×|

Generation improved by 40.3%, 11.0% and 11.1%, respectively. Reversing run
order preserved the improvement in all three models: generation speedups
were 1.403–1.404× for Q1_0, 1.109–1.111× for PQ2_0 and 1.109–1.114× for
PTQ1_0. These are end-to-end, passively cooled results, not fixed-frequency
kernel microbenchmarks: sampled clocks ranged from 1008 to 1512 MHz, and
per-run peak temperatures ranged from 82.7 to 85.4 °C. Do not compare these
ratios against the older, differently controlled table above.

**Recommendation: submit an upstream PR.** All three formats improved in
both run orders, and Cortex-A35 QEMU checks passed 234,240 bit-identical
NEON/reference comparisons per compiler with GCC 12.2 and Buildroot GCC
13.4, including an independent integer oracle for unit-scale cases. The
change leaves dotprod/i8mm paths intact; no Bonsai repack/GEMV path is
selected on base ARMv8.0 at this pin. Submission itself remains pending.

Raw JSON, cooldowns, one-second temperature/frequency samples, library
hashes, disassembly and the [summary](results/2026-11-02-neon/summary.json)
are retained in [results/2026-11-02-neon/](results/2026-11-02-neon/).
The [provenance report](results/2026-11-02-neon/build-provenance.txt) explains
why the archive builds' banner commit is not the authoritative source pin.
The benchmark exited successfully, original CPU governors were restored
byte-for-byte, and the original app process was resumed. No configuration
file or thermal trip point was changed.
