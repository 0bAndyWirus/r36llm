# Phase-aware CPU frequency experiment

On 2026-11-03, one ordered performance-then-phase pair compared the installed PrismML `llama-bench` and default Ternary-Bonsai-2-2B-PTQ1_0 model on the RK3326, with four threads. The experimental phase policy used the performance governor for prompt processing and a 1416 MHz CPU maximum during generation; the comparison used performance without that cap. The app was suspended, the backlight was off, and devfreq settings were unchanged. Binary and model hashes are in `hashes.txt`.

For each sustained measurement, the CPU first used powersave until both thermal zones were at or below 55 °C. Switching settings raised the sampled start temperatures: performance started at 56.818 °C and phase at 55.909 °C. Each measurement ran three back-to-back `llama-bench -p 0 -n 64 -t 4 -r 1 --no-warmup -o json` trials, lasting at least 180 seconds total. The hottest thermal zone, CPU frequency and thermal cooling-device states were sampled every two seconds. Throughput is 192 tokens divided by the sum of the three reported generation times; elapsed run time includes intervening overhead.

| Policy | Elapsed | Sustained t/s | First / last trial t/s | Peak temperature | CPU thermal throttling |
|---|---:|---:|---:|---:|---|
| Performance | 238 s | 0.842 | 0.873 / 0.823 | 83.461 °C | Yes; cooling state up to 5 |
| Phase, 1416 MHz generation cap | 242 s | 0.830 | 0.858 / 0.812 | 83.846 °C | Yes; cooling state up to 5 |

Separate cool-start headless app runs measured time to first token with the prompt `Count from 1 to 100, separated by spaces.`, four threads, seed 42, one generated token and the prompt cache disabled. TTFT was 35.558 s for performance and 36.744 s for phase. These single measurements include prompt processing but exclude model loading; they do not establish a repeatable TTFT difference.

**Conclusion:** Phase was slower in one ordered pair; it is not shipped. A counterbalanced BA repeat was not tested. Keep the existing performance default. The thermal maximum and throughput differences are single-pair observations, not evidence of a general performance ranking.

The raw trial JSON, cooldown logs, telemetry, TTFT output, settings snapshot and device-side runner are retained here. The runner's transferred SHA-256 was `121c2b4703ffc445f4a959d0eabb5f5491ac05def6c1fdb8a03cb0b30a7659cc`. After the run, the original configuration was restored byte-for-byte, the original CPU governor and maximum frequency were restored, and the app was resumed.
