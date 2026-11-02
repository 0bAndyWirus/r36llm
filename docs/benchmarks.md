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

## Where the time goes

Measured 2026-11-02 with a tiny [`cb_eval` profiler](results/2026-11-02-profile/profile.cpp), PrismML pin `5628c7338963b00a598f2a588fd09a79af6d70db` plus the current `0001` NEON patch, Buildroot GCC 13.4.0, `-O2 -march=armv8-a`, OpenMP and four threads. Buildroot's toolchain/sysroot volume was mounted read-only; the profiler and matching `llama-bench` were built separately under `out/profile/`. The app was paused. Before each plain/profile/benchmark process, both thermal zones cooled to at most 55 °C under `powersave`, then the runner selected `performance`. Temperatures immediately after that switch were 54.2–55.9 °C at the hotter zone.

These are short-context measurements: five one-token decode steps at positions 0–4 and three independent eight-token prompt batches, with excluded warmups. Prompt batches request logits only for their last token. The separate comparison ran `llama-bench -p 8 -n 8 -t 4 -r 3 -o json` with normal warmup, using the same patched libraries. Do not compare these small-batch, short runs directly with the earlier `pp64/tg32` or sustained-generation tables.

|Model / workload|Plain median ms|Profile median ms|Sum of node intervals, median ms|llama-bench ms|llama-bench t/s|Profile vs benchmark|
|---|---:|---:|---:|---:|---:|---:|
|2-2B PTQ1_0 / one decode token|959.58|984.07|973.21|1049.26|0.953|-6.2%|
|2-2B PTQ1_0 / prompt8 batch|5504.59|5611.67|5609.35|5456.98|1.466|+2.8%|
|1.7B PQ2_0 / one decode token|615.67|629.45|627.99|677.90|1.475|-7.1%|
|1.7B PQ2_0 / prompt8 batch|3950.52|4040.05|4038.42|3913.65|2.044|+3.2%|

All totals agree with the matching benchmark within 7.2%, inside the 15% target. The callback increased paired plain wall times by 1.9–2.6%. It splits execution into one-node graphs and forces a backend synchronization after every node, so its timings include dispatch/planning and OpenMP-region overhead; tiny ops can be disproportionately inflated. CSV formatting happens outside timed steps. There are 1557 profiled nodes per step for 2-2B and 989 for 1.7B.

The processes started cool but did not stay at a fixed clock: sampled peaks were 80.8–82.3 °C, thermal cooling activated, and sampled frequencies ranged from 1008 to 1512 MHz. The benchmark runs prompt trials before generation, whereas the profiler measures generation first. **[INFERENCE]** Different thermal histories, context sizes and median-versus-mean aggregation explain part of the remaining gap; the signed benchmark difference is not a measure of callback overhead. No thermal limits were changed.

### Operation types

Cells are **median ms (% of profiled wall time)**, summing each op across a trial before taking its median. The complete table, including elementwise ops, copies and metadata-only graph nodes, is in [operations.csv](results/2026-11-02-profile/operations.csv). Independent medians need not sum exactly to the median wall time.

|ggml op|2-2B decode|2-2B prompt8|1.7B decode|1.7B prompt8|
|---|---:|---:|---:|---:|
|MUL_MAT|856.69 (87.06%)|5269.98 (93.91%)|603.77 (95.92%)|3958.77 (97.99%)|
|GATED_DELTA_NET|35.29 (3.59%)|178.06 (3.17%)|—|—|
|GET_ROWS|26.03 (2.65%)|27.91 (0.50%)|0.11 (0.02%)|0.41 (0.01%)|
|CPY|13.10 (1.33%)|15.45 (0.28%)|—|—|
|RMS_NORM|2.97 (0.30%)|7.07 (0.13%)|3.90 (0.62%)|15.93 (0.39%)|
|ROPE|0.37 (0.04%)|0.92 (0.02%)|1.96 (0.31%)|9.11 (0.23%)|
|FLASH_ATTN_EXT, including softmax|0.39 (0.04%)|3.02 (0.05%)|2.42 (0.38%)|15.94 (0.39%)|

There is no standalone `SOFT_MAX` node in either measured graph: softmax is fused inside `FLASH_ATTN_EXT`, and the callback cannot separate its internal time. Including scale multiplications and L2 normalization, all norms together cost 5.24/13.87 ms for 2-2B decode/prompt8 and 6.77/27.86 ms for 1.7B.

### Weight tensors and projections

The q/k/v/o, FFN, linear-attention qkv/gate/output and embedding weights use **PTQ1_0** in 2-2B and **PQ2_0** in 1.7B, read from original GGUF tensor descriptors rather than inferred from model filenames or runtime repacking. Norm weights are F32. The hybrid 2-2B model keeps its linear-attention alpha/beta projections, convolution and state parameters in F32. Every weight's exact type, shape and byte size is retained in the `*-weights.csv` files; [tensors.csv](results/2026-11-02-profile/tensors.csv) has per-node/per-layer median timings and runtime source types.

|Projection, summed across layers|2-2B decode|2-2B prompt8|1.7B decode|1.7B prompt8|
|---|---:|---:|---:|---:|
|FFN gate|137.02 (13.92%)|1073.55 (19.13%)|122.70 (19.49%)|940.71 (23.28%)|
|FFN up|137.97 (14.02%)|1073.94 (19.14%)|123.35 (19.60%)|946.63 (23.43%)|
|FFN down|136.66 (13.89%)|1079.58 (19.24%)|123.01 (19.54%)|950.85 (23.54%)|
|Output / lm_head|223.58 (22.72%)|239.46 (4.27%)|104.57 (16.61%)|107.89 (2.67%)|
|Dense attention q|23.01 (2.34%)|186.77 (3.33%)|42.21 (6.71%)|329.75 (8.16%)|
|Dense attention k|3.01 (0.31%)|24.37 (0.43%)|21.45 (3.41%)|175.72 (4.35%)|
|Dense attention v|3.01 (0.31%)|24.18 (0.43%)|22.05 (3.50%)|169.61 (4.20%)|
|Dense attention o|11.71 (1.19%)|93.05 (1.66%)|42.28 (6.72%)|331.60 (8.21%)|
|Linear attention fused qkv|102.84 (10.45%)|844.78 (15.05%)|—|—|
|Linear attention gate|35.62 (3.62%)|283.57 (5.05%)|—|—|
|Linear attention o|35.09 (3.57%)|285.21 (5.08%)|—|—|
|Linear attention alpha/beta, F32|2.47 (0.25%)|35.80 (0.64%)|—|—|

2-2B is a Qwen3.5 hybrid: 18 linear-attention layers and six dense-attention layers. Its fused qkv projection cannot be honestly divided into separate q/k/v timings; its dense q projection also includes the attention gate. 1.7B is Qwen3 with 28 dense-attention layers. Both use **tied `token_embd.weight` for the output head**, not a separate `output.weight`: 2048 × 248320 PTQ1_0 elements (111.25 MB) for 2-2B and 2048 × 151669 PQ2_0 elements (82.51 MB) for 1.7B. This large-vocabulary matmul alone consumes 23%/17% of decode time, but runs only once per prompt batch here.

For 2-2B, most `GET_ROWS` time gathers recurrent `cache_s_l*` state, not token embeddings. Gated-delta updates cost another 35.29 ms per decode token; linear-attention convolution costs 2.27 ms. Hadamard rotations cost only 4.21 ms (0.43%), so they are not the first target.

### Three optimization targets, ranked

The following gain estimates are **[INFERENCE]**, not measured improvements. They assume a 20% reduction in the named group's execution time, with everything else unchanged.

1. **Specialize low-bit FFN matmul for A35 and small prompt batches.** Gate/up/down consume 41.8% of 2-2B decode and 58.6% of 1.7B decode, rising to 57.5%/70.3% of prompt8. Target the 2048 ↔ 6144 shapes in the PTQ1_0/Q8_0 and PQ2_0/Q8_K paths: tile rows in NEON and reuse unpacked weight blocks across prompt tokens rather than repeating one-row dot work. Keep the packed model and bounded tile scratch; fully expanding all ternary weights would exceed this device's RAM budget. A 20% group-time reduction saves about **8.4%/11.7% decode latency** and **11.5%/14.1% prompt latency**.
2. **Optimize the tied vocabulary-head GEMV without pruning vocabulary.** Use cache-blocked row tiles/prefetching and reuse activation preparation for the 248320/151669 output rows. Preserve every logit; optimizing sampling or softmax would miss the measured cost. A 20% head-time reduction saves about **4.5%/3.3% decode latency**, but less than 1% of these prompt batches. Shared dot-kernel improvements may benefit both this and target 1; do not count overlapping gains twice.
3. **Remove avoidable hybrid recurrent-state gathers/copies, then tune the gated-delta kernel.** In 2-2B, `GET_ROWS` + `CPY` + `GATED_DELTA_NET` total about 74.4 ms (7.6%) per decode token. A direct cache-row/state-update path should avoid the full-state gather while retaining the same recurrence; then vectorize the update if still worthwhile. A 20% group-time reduction saves about **1.5% decode latency**; eliminating the measured gathers alone has a 2.6% ceiling. This target does not apply to dense-only 1.7B. Norms, RoPE and fused attention/softmax are too small at this context length to outrank these targets.

Raw trials, GGUF descriptors, thermal traces, profiler/build/runner sources, [method](results/2026-11-02-profile/method.txt) and [summary](results/2026-11-02-profile/summary.csv): [results/2026-11-02-profile/](results/2026-11-02-profile/). Transfer hashes matched before importing results. The original app PID 251 was resumed, all original CPU governors were restored and verified, `config.ini` remained byte-identical, and the isolated device tools/results directory was removed after retrieval.
