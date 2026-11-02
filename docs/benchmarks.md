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
