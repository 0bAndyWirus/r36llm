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
