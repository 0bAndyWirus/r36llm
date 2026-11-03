# References and credits

r36llm builds on the work credited below. These categories distinguish dependencies and applied techniques from experiments and research leads; citing a paper does not mean its algorithm is in the release. Measurements are local observations, not reproductions of the cited papers’ results. Online sources were inspected on 2026-11-03.

## 1. Software and data this project builds on

Models are downloaded separately; the release image does not bundle them. Code licenses and model licenses are independent. The experimental mainline inputs below are credited separately from the default BSP image.

| Software or data; credited authors | License | What r36llm uses it for / source trail |
|---|---|---|
| [Ternary-Bonsai-2-2B GGUF](https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf), PrismML; base [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B), Qwen | Apache-2.0 for both model cards | Default `Ternary-Bonsai-2-2B-PTQ1_0.gguf`; `scripts/fetch-models.ps1`. The publisher explicitly identifies Qwen3.5-2B as the base. |
| [Bonsai-1.7B](https://huggingface.co/prism-ml/Bonsai-1.7B-gguf), [Ternary-Bonsai-1.7B](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf), [Bonsai-4B](https://huggingface.co/prism-ml/Bonsai-4B-gguf), PrismML | Apache-2.0 per model card | Optional Q1_0/PQ2_0 models downloaded by `scripts/fetch-models.ps1` and compared in [benchmarks](benchmarks.md). These are distinct checkpoints, not interchangeable quantizations of the default model. |
| [SmolLM2-135M-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct), Hugging Face TB; [GGUF](https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF), bartowski | Apache-2.0 for base and GGUF model cards | Optional Q4_0 download and standalone benchmark; no speculative draft integration. |
| [PrismML llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp/tree/5628c7338963b00a598f2a588fd09a79af6d70db), PrismML and the ggml authors; upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) and [ggml](https://github.com/ggml-org/ggml) | MIT | CPU inference, tensor kernels, model loading, tokenizer, sampler, state APIs and CLI tools. `br2-external/package/prism-llama-cpp/prism-llama-cpp.mk` pins `5628c7338963b00a598f2a588fd09a79af6d70db`; three local patches adapt it. |
| [Spleen](https://github.com/fcambus/spleen), Frederic Cambus | BSD-2-Clause | Embedded 12×24 UI font and boot-image lettering; notice retained in `app/src/font.h`. |
| [Buildroot 2025.02.19](https://github.com/buildroot/buildroot/blob/2025.02.19/COPYING), Buildroot contributors | GPL-2.0-or-later, with file-specific exceptions; built packages retain their own licenses | Root filesystem, cross-toolchain and image integration in `scripts/br.sh` and `br2-external/`. |
| [arkos.bsp.4.4](https://github.com/lcdyk0517/arkos.bsp.4.4/tree/382f9c6ddcb4a8d4f0162228305545e647cca97c), lcdyk0517, Linux and BSP contributors | Kernel GPL-2.0, except where individual components state otherwise | Default Linux 4.4 kernel/modules and RK3326 board support; `scripts/bsp/build-kernel.sh`. |
| [exfat-linux backport](https://github.com/christianhaitian/exfat-linux/blob/68072a2dc3bf9d73e8bda9b82fa3f93a7e9ff0a5/super.c), christianhaitian and Samsung Electronics contributors | Inspected source header GPL-2.0-or-later; retain per-file terms | exFAT support imported into the BSP by `scripts/bsp/build-kernel.sh`. |
| [Clone-u-boot 5606e80](https://github.com/lcdyk0517/Clone-u-boot/tree/5606e804ffe8f9e5427d55c8da04c638f01a9391), Christian Haitian, Hardkernel, lcdyk0517 and [U-Boot](https://github.com/u-boot/u-boot) contributors | GPL-2.0-family and component-specific terms; see fork’s `Licenses/` | Default vendor-matching source-built bootloader; `scripts/bsp/build-vendor-uboot.sh`. The previous `4820a71` build remains selectable. |
| Vendor `rg351v-uboot.dtb` / [`rg351mp-uboot.dts` lineage](https://github.com/lcdyk0517/Clone-u-boot/blob/5606e804ffe8f9e5427d55c8da04c638f01a9391/arch/arm/dts/rg351mp-uboot.dts), vendor U-Boot and upstream contributors | GPL-2.0+ lineage; original authored source of the exact vendor blob is not established | `scripts/bsp/rg351v-uboot.dts` is an attributed vendor-DTB decompilation. DTC 1.5.0 rebuilds the 59,523-byte display DTB byte-identically (SHA-256 `d7cfe8a0dec06842e08ec3199fb648ead2c88ee735aa7b725eb298a78693a41b`); it is separate from Linux's board DTB. |
| [RK3326 boot firmware](https://github.com/rockchip-linux/rkbin/tree/a92d5e7df36cd1fac4bab24bc953b145fc0159a1/bin/rk33), Rockchip Electronics | Rockchip repository binary terms, not an open-source license; applicability to the historical removed binaries remains unconfirmed; [retained license](../THIRD-PARTY/firmware/LICENSE) | Default DDR v1.10, miniloader v1.12, BL31 v1.14 and BL32 v1.10 match the working Panel 8 card's firmware payloads. Optional variant A retains newer miniloader/trust. [Exact binaries, provenance and licensing caveat](../THIRD-PARTY/firmware/NOTICE). |
| [Arch R](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/LICENSE.md), Arch R and ROCKNIX contributors | Original scripts/software GPL v2; included works and branding have separate terms | Experimental mainline kernel configuration, patch layers, DTS and U-Boot integration; `scripts/mainline/common.sh`, [mainline notes](mainline.md). |
| [Generic MIPI-DSI panel driver](https://github.com/archr-linux/Arch-R/blob/6b4904f99bef3fffab490b5ea70ac7de15735885/projects/ArchR/packages/linux-drivers/generic-dsi/sources/panel-generic-dsi.c), Arch R, with earlier Purism SPC driver credit | GPL-2.0 | Panel driver copied into the experimental mainline kernel. |
| [archr-singleadc-joypad](https://github.com/archr-linux/archr-joypad/blob/4a8392c1a15a9cf2cab43750c3246d53d6410301/archr-singleadc-joypad.c), ROCKNIX and ARCH-R | GPL-2.0-or-later | Experimental mainline joypad module in `scripts/mainline/build-kernel.sh`. |
| [Arch-R-R36S panel generator](https://github.com/loddv/Arch-R-R36S/blob/fe8aa3d3497e0937ea27123749fcf1a306f84dec/config/mipi-generator/archr-dtbo.py), loddv/Arch-R-R36S and Arch R contributors | Repository notice: original Arch R scripts GPL v2; no separate generator header verified | Converts an exact-board vendor DTB into the experimental mainline panel overlay; `scripts/mainline/build-panel.sh`. This does not establish redistribution rights for the vendor DTB. |
| [Python fdt 0.3.3](https://pypi.org/project/fdt/0.3.3/), Martin Olejar | Apache-2.0 per PyPI metadata | Host-only dependency of the experimental panel generator. |
| [Linux 6.12.114](https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.12.114.tar.xz), Linux contributors; [U-Boot v2025.10](https://github.com/u-boot/u-boot/tree/e50b1e8715011def8aff1588081a2649a2c6cd47), U-Boot contributors; [rkbin](https://github.com/rockchip-linux/rkbin/tree/74213af1e952c4683d2e35952507133b61394862), Rockchip | Linux GPL-2.0 with exceptions; U-Boot component-specific terms; Rockchip binary terms | Experimental mainline path in `scripts/mainline/`, separate from the default BSP. Its firmware uses DDR v2.11, miniloader and BL31; BL32 is disabled. |
| [GNU libc](https://github.com/buildroot/buildroot/blob/2025.02.19/package/glibc/glibc.mk), GNU/glibc contributors | Library material LGPL-2.1-or-later, BSD-3-Clause and MIT; programs GPL-2.0-or-later | Enabled C runtime; license summary from pinned Buildroot package metadata. |
| [BusyBox](https://github.com/buildroot/buildroot/blob/2025.02.19/package/busybox/busybox.mk), BusyBox contributors | GPL-2.0 and bzip2-1.0.6 material | Init and userspace utilities; enabled image package. |
| [Dropbear](https://github.com/buildroot/buildroot/blob/2025.02.19/package/dropbear/dropbear.mk), Dropbear contributors | MIT, BSD-2-Clause and public-domain material | SSH service; enabled image package. |
| [dosfstools](https://github.com/buildroot/buildroot/blob/2025.02.19/package/dosfstools/dosfstools.mk), dosfstools contributors | GPL-3.0-or-later | `mkfs.fat`; enabled image package. |
| [util-linux](https://github.com/buildroot/buildroot/blob/2025.02.19/package/util-linux/util-linux.mk), util-linux contributors | Multiple GPL, LGPL, BSD, ISC and MIT terms | Disk utilities including first-boot `sfdisk` and `blockdev`; enabled image package. |
| [GCC runtime libraries](https://github.com/buildroot/buildroot/blob/2025.02.19/package/gcc/gcc-final/gcc-final.mk), GNU/GCC contributors | GPL-3.0 with GCC Runtime Library Exception for applicable runtime libraries | C++/OpenMP support enabled for the app and engine; actual installed libraries depend on the resolved build. |

The six runtime-package summaries use pinned Buildroot metadata, not a claim that every listed subcomponent appears in the image. This credit list does not replace the release’s Buildroot `legal-info` output, corresponding-source bundles, or individual copyright/license notices. Exact Rockchip firmware source revisions and the vendor Panel 8 DTB’s redistribution terms have not been established; see the retained firmware notice and [mainline provenance caveat](mainline.md).

## 2. Techniques that directly informed shipped code

These entries have an explicit implementation or method trail. Patch names below are under `br2-external/package/prism-llama-cpp/`; their correctness harnesses are in its `tests/` directory.

- Google LLC and ruy contributors. “The ruy matrix multiplication library.” Open-source software, 2019–present. [Repository](https://github.com/google/ruy); [ARM64 kernel source](https://raw.githubusercontent.com/google/ruy/master/ruy/kernel_arm64.cc). Apache-2.0.

  The independent-accumulator and activation-reuse principles informed the two-row PTQ1_0/PQ2_0 kernels in `0002-arm-neon-bonsai-two-rows.patch`. The [method note](results/2026-11-03-speedups/lut-feasibility.txt) explicitly identifies this source and says no ruy code was copied. r36llm does not link ruy.

- Benoit Jacob, Google, David Mansell, and gemmlowp contributors. “gemmlowp: a small self-contained low-precision GEMM library.” Open-source software, 2017–present. [Repository](https://github.com/google/gemmlowp); [pinned kernel benchmark source](https://raw.githubusercontent.com/google/gemmlowp/36212ad3651871bc3e9a599f1a6d5324778aea25/standalone/neon-gemm-kernel-benchmark.cc). Apache-2.0.

  The same [method note](results/2026-11-03-speedups/lut-feasibility.txt) credits gemmlowp alongside ruy for the shipped two-row scheduling principles. `0002` reuses each activation load and scale conversion across two weight rows while preserving per-row reduction order; it does not import gemmlowp or expand the model to INT8.

- karusrus and PrismML contributors. “arm: NEON + i8mm vec_dot for PTQ1_0.” PrismML-Eng/llama.cpp PR #290, merged October 7, 2026. [PR](https://github.com/PrismML-Eng/llama.cpp/pull/290). Code: MIT.

  This is code reuse through the pinned PrismML fork, not a new r36llm decoder. Its `ggml_ptq1_0_decode_neon` is already in the pin; local patches `0001` and `0002` call it. The [method note](results/2026-11-03-speedups/lut-feasibility.txt) records that provenance. The A35 uses widening multiplies, not the PR’s SDOT/SMMLA back ends.

- Georgi Gerganov and the ggml authors. *llama.cpp: LLM inference in C/C++*. Open-source software, 2023–present, MIT. [Project](https://github.com/ggml-org/llama.cpp); [server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md).

  r36llm uses the pinned fork’s `llama_state_seq_get_size`, `llama_state_seq_get_data` and `llama_state_seq_set_data` APIs to serialize and restore an exact stable system prefix. [Benchmarks](benchmarks.md#app-overhead) describe both memory and disk snapshots and the model/prompt/engine cache key. This is an application-specific cache, not an adoption of upstream server cache policy or its flags.

**Other shipped techniques, without a demonstrated paper-to-code attribution.** `0001-arm-neon-armv8.0-bonsai-dot.patch` documents widening INT8 multiply-accumulate into bounded INT16 lanes, followed by integer reduction before scaling. It bounds four products per lane by 1024 and sixteen by 4096, including Q8 −128 and PQ2’s fourth code. The generic upstream dots and the independent integer decoder in `tests/test-bonsai-neon.c` are the numerical references. This resembles established low-precision kernel practice, but the repository does not establish that Jacob et al. or XNNPACK supplied this implementation; those are credited as background below.

The opt-in `0003-qwen35-restricted-output-head.patch` computes only selected original output rows, leaves input embeddings/tokenization intact and assigns excluded logits −∞. The [method](results/2026-11-03-vocab-head/method.txt) records 133,951 retained IDs out of 248,320 and a sustained device AB/BA gain of 6.04%, with 1.53 MiB higher peak RSS. It is off by default and changes the available output distribution. The repository does not attribute this implementation to FR-Spec or vocabulary-retraining work: neither frequency-ranked speculative drafting nor tokenizer replacement is implemented.

## 3. Evaluated or measured, not shipped

The three DVFS sources below are related research, not claims that their full systems were ported. The [local phase experiment](results/2026-11-03-phase-dvfs/README.md) used performance during prefill and a 1416 MHz maximum during generation. In one ordered pair, sustained throughput was 0.842 t/s for performance versus 0.830 t/s for phase; peaks were 83.461 °C and 83.846 °C, and both throttled. Separate single TTFT measurements were 35.558 s and 36.744 s. No counterbalanced repeat was run. The phase policy is not shipped; performance remains the default.

- Zongpu Zhang, Pranab Dash, Qiang Xu, Y. Charlie Hu, Jian Li, and Haibing Guan. “Rethinking DVFS for Mobile LLMs: Unified Energy-Aware Scheduling with CORE.” *Proceedings of Machine Learning and Systems*, vol. 8, pp. 186–198, 2026. [Proceedings page](https://proceedings.mlsys.org/paper_files/paper/2026/hash/136b9a13861308c8948cd308ccd02658-Abstract-Conference.html); [full paper](https://proceedings.mlsys.org/paper_files/paper/2026/file/136b9a13861308c8948cd308ccd02658-Paper-Conference.pdf). **Code license:** **unverified**. The paper says its llama.cpp extension was released, but a repository and license could not be verified from the primary material and searches consulted.

  Related phase-aware DVFS literature; r36llm did not implement CORE’s CPU/GPU coordinator.

- Weisi Yang and Stephen Xia. “PELM: Power Efficient On-Device LLM Inference with Speculative Decoding and Dynamic Voltage Frequency Scaling.” *Proceedings of the 2026 ACM/IEEE International Conference on Embedded Artificial Intelligence and Sensing Systems*, pp. 438–451, 2026. [Primary paper](https://arxiv.org/html/2609.09662); DOI: 10.1145/3774906.3802783; [authors’ artifact](https://github.com/imec-nu/PELM). **Code license:** **unverified**; the opened repository listing did not show a license file. The paper’s CC BY 4.0 notice is not a software license.

  Related thermal/DVFS literature; r36llm did not implement PELM’s reinforcement-learning controller, speculation or reduced verification.

- Jie Xiao, Qianyi Huang, Xu Chen, and Chen Tian. “Understanding Large Language Models in Your Pockets: Performance Study on COTS Mobile Devices.” *arXiv preprint* arXiv:2410.03613, version 3, 2025. [Opened primary version](https://arxiv.org/html/2410.03613v3); [arXiv record](https://arxiv.org/abs/2410.03613). **Code license:** a study-specific code artifact and license were **not verified**. The study uses existing llama.cpp and MLC LLM engines; their licenses should not be presented as a license for unlocated study code.

  Related measurement methodology for separating prefill/decode, thread counts, frequency and temperature; not a scheduler shipped by r36llm.

- Ankk98. “Feature Request: skip redundant recurrent-state gather when n_rs == 1 && n_seqs == 1.” llama.cpp issue #28841, opened September 13, 2026; open when inspected. [Issue](https://github.com/ggml-org/llama.cpp/issues/28841). The implementation context is llama.cpp, MIT; this is a proposal, not a merged optimization.

  The local indexed-state GDN experiment is related to the issue’s gather-elimination motivation, not an implementation of its exact identity-view proposal. It preserved a runtime source-row index under single-token/single-sequence guards. [Measured AB/BA result](results/2026-11-03-speedups/state-method.txt): generation 1.113824 → 1.128572 t/s (+1.324%); prefill −0.150%. It was excluded because operator checks did not qualify the full cache lifecycle. Only `rejected-state-gather.patch` remains in the evidence directory; it is not a package patch.

- Loubna Ben Allal, Anton Lozhkov, Elie Bakouch, Gabriel Martín Blázquez, Guilherme Penedo, Lewis Tunstall, Andrés Marafioti, Hynek Kydlíček, Agustín Piqueres Lajarín, Vaibhav Srivastav, Joshua Lochner, Caleb Fahlgren, Xuan-Son Nguyen, Clémentine Fourrier, Ben Burtenshaw, Hugo Larcher, Haojun Zhao, Cyril Zakka, Mathieu Morlon, Colin Raffel, Leandro von Werra, and Thomas Wolf. “SmolLM2: When Smol Goes Big—Data-Centric Training of a Small Language Model.” arXiv:2502.02737, 2025. [Paper](https://arxiv.org/abs/2502.02737); [model card](https://huggingface.co/HuggingFaceTB/SmolLM2-135M).

  The [standalone device benchmark](benchmarks.md) measured SmolLM2-135M-Instruct Q4_0 at 10.13 generation t/s with an 88 MB file. No Bonsai draft acceptance or combined-runtime memory result was measured, and no speculative assistant is shipped. Its tokenizer differs from the default Bonsai tokenizer.

## 4. Surveyed for future work

These are research/background credits, **not shipped implementations or promised speedups**. None establishes a ternary Bonsai speedup on Cortex-A35. GPU/NPU/custom-ISA systems can inform design without being portable to this device; sparsity, reduced heads and approximate caches may change outputs, while speculation requires correct verification and hybrid-state rollback.

### Low-bit kernels and layouts

- Xiangyu Li, Chengyu Yin, Weijun Wang, Jianyu Wei, Ting Cao, and Yunxin Liu. “Vec-LUT: Vector Table Lookup for Parallel Ultra-Low-Bit LLM Inference on Edge Devices.” MobiSys 2026, pp. 216–230. [Paper](https://arxiv.org/html/2512.06443v2); [code](https://github.com/OpenBitSys/vlut.cpp), MIT. DOI: 10.1145/3745756.3809200.
- Darshan C. Ganji, Saad Ashfaq, Ehsan Saboori, Sudhakar Sah, Saptarshi Mitra, MohammadHossein AskariHemmat, Alexander Hoffman, Ahmed Hassanien, and Mathieu Léonardon. “DeepGEMM: Accelerated Ultra Low-Precision Inference on CPU Architectures using Lookup Tables.” CVPR Workshops, ECV, 2023. [Paper](https://openaccess.thecvf.com/content/CVPR2023W/ECV/papers/Ganji_DeepGEMM_Accelerated_Ultra_Low-Precision_Inference_on_CPU_Architectures_Using_Lookup_CVPRW_2023_paper.pdf), arXiv:2304.09049. Official code artifact/license not verified; do not confuse it with the later GPU library of the same name.
- Jaeyeon Won, Jeyeon Si, Sam Son, Tae Jun Ham, and Jae W. Lee. “ULPPACK: Fast Sub-8-bit Matrix Multiply on Commodity SIMD Hardware.” Proceedings of Machine Learning and Systems 4, MLSys 2022. [Proceedings](https://proceedings.mlsys.org/paper_files/paper/2022/hash/e09d45e14e9ece7142217550ddd3c4d0-Abstract.html); [paper](https://proceedings.mlsys.org/paper_files/paper/2022/file/e09d45e14e9ece7142217550ddd3c4d0-Paper.pdf). Public author code/license not verified.
- Meghan Cowan, Thierry Moreau, Tianqi Chen, James Bornholt, and Luis Ceze. “Automatic Generation of High-Performance Quantized Machine Learning Kernels.” CGO 2020, pp. 305–316. DOI: 10.1145/3368826.3377912. [Author-hosted paper](https://jamesbornholt.com/papers/quantized-cgo20.pdf); related earlier [arXiv paper](https://arxiv.org/abs/1810.11066). [TVM framework](https://github.com/apache/tvm) is Apache-2.0; exact paper-specific synthesis artifact/license not verified.
- Lei Wang, Lingxiao Ma, Shijie Cao, Quanlu Zhang, Jilong Xue, Yining Shi, Ningxin Zheng, Ziming Miao, Fan Yang, Ting Cao, Yuqing Yang, and Mao Yang. “Ladder: Enabling Efficient Low-Precision Deep Learning Computing through Hardware-aware Tensor Transformation.” OSDI 2024, pp. 307–323. [Publication](https://www.usenix.org/conference/osdi24/presentation/wang-lei); [paper](https://www.usenix.org/system/files/osdi24-wang-lei.pdf); [BitBLAS code](https://github.com/microsoft/BitBLAS), MIT.
- Gunho Park, Baeseong Park, Minsub Kim, Sungjae Lee, Jeonghoon Kim, Beomseok Kwon, Se Jung Kwon, Byeongwook Kim, Youngjoo Lee, and Dongsoo Lee. “LUT-GEMM: Quantized Matrix Multiplication based on LUTs for Efficient Inference in Large-Scale Generative Language Models.” ICLR 2024; arXiv:2206.09557. [Paper](https://arxiv.org/html/2206.09557v4); [code](https://github.com/naver-aics/lut-gemm), Apache-2.0.
- Hyunwoo Oh, KyungIn Nam, Rajat Bhattacharjya, Hanning Chen, Tamoghno Das, Sanggeon Yun, Suyeon Jang, Andrew Ding, Nikil Dutt, and Mohsen Imani. “T-SAR: A Full-Stack Co-design for CPU-Only Ternary LLM Inference via In-Place SIMD ALU Reorganization.” arXiv:2511.13676, 2025 preprint. [Paper](https://arxiv.org/html/2511.13676v1). Public code/RTL artifact and license not verified.

### Activation sparsity

- Zichang Liu, Jue Wang, Tri Dao, Tianyi Zhou, Binhang Yuan, Zhao Song, Anshumali Shrivastava, Ce Zhang, Yuandong Tian, Christopher Ré, and Beidi Chen. “Deja Vu: Contextual Sparsity for Efficient LLMs at Inference Time.” *ICML*, PMLR 202, pp. 22137–22176, 2023. [Proceedings](https://proceedings.mlr.press/v202/liu23am.html) · [paper](https://proceedings.mlr.press/v202/liu23am/liu23am.pdf) · [official code](https://github.com/FMInference/DejaVu).
- Yixin Song, Zeyu Mi, Haotong Xie, and Haibo Chen. “PowerInfer: Fast Large Language Model Serving with a Consumer-grade GPU.” *Proceedings of the ACM SIGOPS 30th Symposium on Operating Systems Principles* (SOSP), 2024. DOI: DOI: 10.1145/3694715.3695964. [Author-hosted proceedings paper](https://ipads.sjtu.edu.cn/_media/publications/song-sosp24.pdf) · [official code](https://github.com/Tiiny-AI/PowerInfer).
- Zhenliang Xue, Yixin Song, Zeyu Mi, Xinrui Zheng, Yubin Xia, and Haibo Chen. “PowerInfer-2: Fast Large Language Model Inference on a Smartphone.” *arXiv preprint* arXiv:2406.06282, version 3, 2024. [Paper](https://arxiv.org/html/2406.06282v3) · [PowerInfer project repository](https://github.com/Tiiny-AI/PowerInfer).
- Yixin Song, Haotong Xie, Zhengyan Zhang, Bo Wen, Li Ma, Zeyu Mi, and Haibo Chen. “Turbo Sparse: Achieving LLM SOTA Performance with Minimal Activated Parameters.” *arXiv preprint* arXiv:2406.05955, 2024. [Paper](https://arxiv.org/html/2406.05955) · [PowerInfer inference code](https://github.com/Tiiny-AI/PowerInfer).
- Donghyun Lee, Je-Yong Lee, Genghan Zhang, Mo Tiwari, and Azalia Mirhoseini. “CATS: Contextually-Aware Thresholding for Sparsity in Large Language Models.” *Conference on Language Modeling* (COLM), 2024; arXiv:2404.08763v4. [Paper](https://arxiv.org/html/2404.08763v4) · [official repository](https://github.com/ScalingIntelligence/CATS) · [author publication page](https://scalingintelligence.stanford.edu/pubs/CATSpaper/).
- James Liu, Pragaash Ponnusamy, Tianle Cai, Han Guo, Yoon Kim, and Ben Athiwaratkun. “Training-Free Activation Sparsity in Large Language Models.” *International Conference on Learning Representations* (ICLR), 2025. [Paper](https://arxiv.org/html/2408.14690v3) · [official repository](https://github.com/FasterDecoding/TEAL).
- Iman Mirzadeh, Keivan Alizadeh, Sachin Mehta, Carlo C Del Mundo, Oncel Tuzel, Golnoosh Samei, Mohammad Rastegari, and Mehrdad Farajtabar. “ReLU Strikes Back: Exploiting Activation Sparsity in Large Language Models.” *International Conference on Learning Representations* (ICLR), 2024. [Conference paper](https://proceedings.iclr.cc/paper_files/paper/2024/file/6cf669c222ad13f60d503736fb2bd15b-Paper-Conference.pdf) · [proceedings record](https://proceedings.iclr.cc/paper_files/paper/2024/hash/6cf669c222ad13f60d503736fb2bd15b-Abstract-Conference.html).

### Vocabulary and output heads

- Weilin Zhao, Tengyu Pan, Xu Han, Yudi Zhang, Ao Sun, Yuxiang Huang, Kaihuo Zhang, Weilun Zhao, Yuxuan Li, Jie Zhou, Hao Zhou, Jianyong Wang, Zhiyuan Liu, and Maosong Sun. “FR-Spec: Accelerating Large-Vocabulary Language Models via Frequency-Ranked Speculative Sampling.” *ACL*, 2025, pp. 3909–3921. [Published paper](https://aclanthology.org/2025.acl-long.198/); [experimental details](https://arxiv.org/html/2502.14856v2). The published author list is longer than that of the opened arXiv version.
- Yuta Nozaki, Dai Nakashima, Ryo Sato, Naoki Asaba, and Shintaro Kawamura. “Efficient Vocabulary Reduction for Small Language Models.” *COLING Industry Track*, 2025, pp. 771–783. [Publication](https://aclanthology.org/2025.coling-industry.64/); [paper](https://aclanthology.org/2025.coling-industry.64.pdf).
- Tavor Z. Baharav, Ryan Kang, Colin Sullivan, Mo Tiwari, Eric Luxenberg, David Tse, and Mert Pilanci. “Adaptive Sampling for Efficient Softmax Approximation.” *Advances in Neural Information Processing Systems 37*, 2024. [Publication](https://proceedings.neurips.cc/paper_files/paper/2024/hash/d52dbd66219dc4e432e0bd4f9c25c4c3-Abstract-Conference.html); [paper](https://proceedings.neurips.cc/paper_files/paper/2024/file/d52dbd66219dc4e432e0bd4f9c25c4c3-Paper-Conference.pdf).
- Patrick H. Chen, Si Si, Yang Li, Ciprian Chelba, and Cho-Jui Hsieh. “GroupReduce: Block-Wise Low-Rank Approximation for Neural Language Model Shrinking.” NeurIPS 31, 2018. [Publication](https://proceedings.neurips.cc/paper_files/paper/2018/hash/a2b8a85a29b2d64ad6f47275bf1360c6-Abstract.html); [paper](https://proceedings.neurips.cc/paper_files/paper/2018/file/a2b8a85a29b2d64ad6f47275bf1360c6-Paper.pdf). Author code artifact/license not verified.

### Speculative and lookup decoding

- Yaniv Leviathan, Matan Kalman, and Yossi Matias. “Fast Inference from Transformers via Speculative Decoding.” *ICML*, PMLR 202, 2023, pp. 19274–19286. [Publication](https://proceedings.mlr.press/v202/leviathan23a.html); [paper](https://proceedings.mlr.press/v202/leviathan23a/leviathan23a.pdf).
- Daniel Korat, Oren Pereg, Moshe Berchansky, Jonathan Mamou, Joao Gante, Lewis Tunstall, Nadav Timor, and Moshe Wasserblat. “Universal Assisted Generation: Faster Decoding with Any Assistant Model.” Hugging Face/Intel technical blog, October 29, 2024. [Primary article](https://huggingface.co/blog/universal_assisted_generation). This is a technical article, not a peer-reviewed venue.
- Mostafa Elhoushi, Akshat Shrivastava, Diana Liskovich, Basil Hosmer, Bram Wasti, Liangzhen Lai, Anas Mahmoud, Bilge Acun, Saurabh Agarwal, Ahmed Roman, Ahmed Aly, Beidi Chen, and Carole-Jean Wu. “LayerSkip: Enabling Early Exit Inference and Self-Speculative Decoding.” *ACL*, 2024, pp. 12622–12642. [Publication](https://aclanthology.org/2024.acl-long.681/); [paper](https://aclanthology.org/2024.acl-long.681.pdf).
- Jun Zhang, Jue Wang, Huan Li, Lidan Shou, Ke Chen, Gang Chen, and Sharad Mehrotra. “Draft & Verify: Lossless Large Language Model Acceleration via Self-Speculative Decoding.” *ACL*, 2024, pp. 11263–11282. [Published paper](https://aclanthology.org/2024.acl-long.607/); [detailed version](https://arxiv.org/html/2309.08168).
- Yichao Fu, Peter Bailis, Ion Stoica, and Hao Zhang. “Break the Sequential Dependency of LLM Inference Using Lookahead Decoding.” *ICML*, PMLR 235, 2024, pp. 14060–14079. [Publication](https://proceedings.mlr.press/v235/fu24a.html); [paper and hardware](https://arxiv.org/html/2402.02057).
- Apoorv Saxena. “Prompt Lookup Decoding.” Software and experimental report, November 2023. [Original repository](https://github.com/apoorvumang/prompt-lookup-decoding). The repository’s own BibTeX identifies the author and date; this is not a peer-reviewed paper.

### State, scheduling, and prefill

- natemacfadden and llama.cpp maintainers. “Eval bug: llama_memory_seq_rm returns true but doesn’t restore the recurrent state when rolling back entire last decode.” llama.cpp issue #26695, August 2026; closed. [Issue and reproducer](https://github.com/ggml-org/llama.cpp/issues/26695). Runtime code license: MIT.
- Marat Dukhan, Google, Meta/Facebook, and XNNPACK contributors. “XNNPACK: high-efficiency neural-network inference operators.” Open-source software, 2019–present. [Repository and benchmark tables](https://github.com/google/XNNPACK); [license](https://raw.githubusercontent.com/google/XNNPACK/master/LICENSE), BSD-3-Clause.
- Arm Limited and KleidiAI contributors. “KleidiAI.” Open-source microkernel library, 2024–present. [Overview](https://github.com/ARM-software/kleidiai/blob/main/README.md); [kernel/ISA table](https://github.com/ARM-software/kleidiai/blob/main/docs/microkernel_tables.md). Source headers declare Apache-2.0; review per-file notices and third-party licenses.
- Jiayi Yao, Hanchen Li, Yuhan Liu, Siddhant Ray, Yihua Cheng, Qizheng Zhang, Kuntai Du, Shan Lu, and Junchen Jiang. “CacheBlend: Fast Large Language Model Serving for RAG with Cached Knowledge Fusion.” *Proceedings of the Twentieth European Conference on Computer Systems*, pp. 94–109, 2025. [Primary paper](https://arxiv.org/html/2405.16444v3); DOI: 10.1145/3689031.3696098; [code project](https://github.com/LMCache/LMCache). **Code license:** [Apache-2.0](https://github.com/LMCache/LMCache/blob/dev/LICENSE) for the currently linked LMCache repository.
- Daliang Xu, Hao Zhang, Liming Yang, Ruiqi Liu, Gang Huang, Mengwei Xu, and Xuanzhe Liu. “Fast On-device LLM Inference with NPUs.” *Proceedings of the 30th ACM International Conference on Architectural Support for Programming Languages and Operating Systems*, vol. 1, 2025. [Primary paper](https://arxiv.org/html/2407.05858v2); DOI: 10.1145/3669940.3707239; [mllm project](https://github.com/UbiquitousLearning/mllm). **Code license:** the current mllm project is [MIT](https://github.com/UbiquitousLearning/mllm/blob/main/LICENSE); the paper also depends on Qualcomm’s separately licensed QNN stack.
- Ziang Duan, Jiajun Wu, Zetian Chen, Hao Song, Yanwen Deng, Zixuan Shen, Nuobei Xie, Simo Wu, Bolun Wang, Peng Zhou, and Chao Wang. “Unified Lookup-Table Inference with Signed-Digit K/V Caches for Ternary LLMs.” arXiv:2608.03229, 2026 preprint. [Paper](https://arxiv.org/html/2608.03229v1). Code/RTL artifact and software license not verified; the paper’s CC BY 4.0 is not a code license.

### Upstream formats and proposals

- compilade and llama.cpp contributors. “ggml-quants: ternary packing for TriLMs and BitNet b1.58.” llama.cpp PR #8151, merged September 6, 2024. [PR](https://github.com/ggml-org/llama.cpp/pull/8151). Code: MIT.
- khosravipasha / PrismML and llama.cpp contributors. “ggml: add Q1_0 1-bit quantization support (CPU).” llama.cpp PR #21273, merged April 6, 2026. [PR](https://github.com/ggml-org/llama.cpp/pull/21273). Code: MIT.
- khosravipasha / PrismML and llama.cpp contributors. “ggml: add Q2_0 quantization support (CPU).” llama.cpp PR #24448, merged July 7, 2026. [PR](https://github.com/ggml-org/llama.cpp/pull/24448). Code: MIT.
- pl752 and llama.cpp contributors. “ggml-cpu: ARM Repack kernels for Q1_0.” llama.cpp PR #23492, merged September 21, 2026. [PR](https://github.com/ggml-org/llama.cpp/pull/23492). Code: MIT.
- Quentin Danblon (QuentinDanblon). “ggml: add PQ2_0 and PTQ1_0 ternary types; llama: apply Hadamard-folded weights.” llama.cpp PR #29077, September 2026, closed without merge. [PR](https://github.com/ggml-org/llama.cpp/pull/29077); [publisher’s 2B model card](https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf). Code in proposed branch: MIT; model weights: Apache-2.0.
- ansarzeinulla. “Feature Request: [CPU] ARM i8mm 8x8 blocked GEMM/GEMV paths for TQ1_0 and TQ2_0.” llama.cpp issue #27276, August 17, 2026; closed with stale label. [Issue](https://github.com/ggml-org/llama.cpp/issues/27276). Existing runtime: MIT; no implemented patch is established by this issue.
- pl752 and llama.cpp contributors. “ggml-cpu: Optimized Arm NEON cpu q1_0 dot (with plain/DP/I8MM).” llama.cpp PR #23358, opened May 19, 2026; open when inspected. [PR](https://github.com/ggml-org/llama.cpp/pull/23358). Proposed code: MIT.

### Additional background and future decoding work

- Jianyu Wei, Shijie Cao, Ting Cao, Lingxiao Ma, Lei Wang, Yanyong Zhang, and Mao Yang. “T-MAC: CPU Renaissance via Table Lookup for Low-Bit LLM Deployment on Edge.” arXiv:2407.00088, 2024. [Paper](https://arxiv.org/abs/2407.00088); [code](https://github.com/microsoft/T-MAC). The [local LUT feasibility note](results/2026-11-03-speedups/lut-feasibility.txt) explicitly consults T-MAC, but no LUT candidate was implemented or installed.
- Jinheng Wang, Hansong Zhou, Ting Song, Shijie Cao, Yan Xia, Ting Cao, Jianyu Wei, Shuming Ma, Hongyu Wang, and Furu Wei. “Bitnet.cpp: Efficient Edge Inference for Ternary LLMs.” arXiv:2502.11880, 2025. [Paper](https://arxiv.org/abs/2502.11880); [paper code](https://github.com/microsoft/BitNet/tree/paper). TL1/TL2 are explicit design references in the same feasibility note, not kernels used by this release.
- Benoit Jacob, Skirmantas Kligys, Bo Chen, Menglong Zhu, Matthew Tang, Andrew Howard, Hartwig Adam, and Dmitry Kalenichenko. “Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference.” CVPR, 2018, pp. 2704–2713. [Publication](https://openaccess.thecvf.com/content_cvpr_2018/html/Jacob_Quantization_and_Training_CVPR_2018_paper.html). Background for integer inference and accumulator design; no evidence that its training/quantization procedure or kernels were applied to the existing Bonsai checkpoint.
- Fabian Gloeckle, Badr Youbi Idrissi, Baptiste Roziere, David Lopez-Paz, and Gabriel Synnaeve. “Better & Faster Large Language Models via Multi-token Prediction.” ICML, PMLR 235, 2024, pp. 15706–15734. [Publication](https://proceedings.mlr.press/v235/gloeckle24a.html). Future trained multi-token heads, not support already present in r36llm.
- Tianle Cai, Yuhong Li, Zhengyang Geng, Hongwu Peng, Jason D. Lee, Deming Chen, and Tri Dao. “Medusa: Simple LLM Inference Acceleration Framework with Multiple Decoding Heads.” ICML, PMLR 235, 2024, pp. 5209–5235. [Publication](https://proceedings.mlr.press/v235/cai24b.html). Future auxiliary heads/tree verification; no Medusa heads are supplied for the default model.
- Yuhui Li, Fangyun Wei, Chao Zhang, and Hongyang Zhang. “EAGLE: Speculative Sampling Requires Rethinking Feature Uncertainty.” ICML, PMLR 235, 2024, pp. 28935–28948. [Publication](https://proceedings.mlr.press/v235/li24bt.html). Future feature-level drafting, not a shipped speculative path.
- LLVM Project contributors. “Cortex-A53 Scheduling Definitions” (`AArch64SchedA53.td`). LLVM source, inspected 2026; Apache-2.0 WITH LLVM-exception. [Source](https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Target/AArch64/AArch64SchedA53.td). Background for in-order scheduling; an A53 compiler model is not an A35 timing specification, and the shipped engine was built with GCC.

### Related prefix-cache proposals

- Georgi Gerganov (ggerganov) and llama.cpp contributors. “server : host-memory prompt caching.” llama.cpp PR #16391, 2025, MIT. [Proposal and discussion](https://github.com/ggml-org/llama.cpp/pull/16391). Merged upstream; a related server design, not the application cache policy implemented here.
- Moltes94 and llama.cpp contributors. “server: add recurrent state shrink/expand for prompt cache (#22746).” llama.cpp PR #24785, 2026, MIT. [Proposal and discussion](https://github.com/ggml-org/llama.cpp/pull/24785). Open proposal; consulted as a hybrid-state failure-mode reference, not applied.
- hanxiao and llama.cpp contributors. “server: fix prompt cache reuse for hybrid/recurrent models.” llama.cpp PR #21099, 2026, MIT. [Proposal and discussion](https://github.com/ggml-org/llama.cpp/pull/21099). Closed without merge; the reported diagnosis was challenged in review, not treated as proof of a defect in the pinned fork.
- bcmyguest and llama.cpp contributors. “server : add --cache-reuse-hybrid for recurrent/hybrid models.” llama.cpp PR #29918, 2026, MIT. [Proposal and discussion](https://github.com/ggml-org/llama.cpp/pull/29918). Open experimental proposal; mid-prompt reuse is not implemented or assumed exact here.

**Attribution boundary.** The [LUT method note](results/2026-11-03-speedups/lut-feasibility.txt) explicitly leaves #23358’s XOR/subtract alternative unimplemented; the shipped Q1 kernel uses widening multiply-accumulate instead. #8151’s TQ1_0/TQ2_0 group-256 formats are not the default model’s PTQ1_0 group-128 format. XNNPACK, Jacob et al., FR-Spec and the vocabulary-reduction papers remain background because matching a broad technique is not evidence that their code or algorithm was adopted. T-MAC and bitnet.cpp reached a design-feasibility analysis only. Public repository availability or a paper’s license does not by itself establish code-redistribution rights.

## 5. BibTeX

Paper records reuse the verified bibliography; added background papers use their primary publication metadata. Software, articles and issue/PR records are included as such, not labeled peer-reviewed work. Author order for CATS follows arXiv v4; PowerInfer-2 identifies v3. For *ReLU Strikes Back*, the conference PDF prints “Keivan Alizadeh,” while proceedings metadata uses “Keivan Alizadeh-Vahid”; the record follows the PDF. Access date for online sources: 2026-11-03.

```bibtex
@inproceedings{li2026veclut,
 author={Li, Xiangyu and Yin, Chengyu and Wang, Weijun and Wei, Jianyu and Cao, Ting and Liu, Yunxin},
 title={Vec-LUT: Vector Table Lookup for Parallel Ultra-Low-Bit LLM Inference on Edge Devices},
 booktitle={Proceedings of the 24th Annual International Conference on Mobile Systems, Applications and Services},
 pages={216--230}, year={2026}, doi={10.1145/3745756.3809200}, url={https://arxiv.org/html/2512.06443v2}
}

@inproceedings{ganji2023deepgemm,
 author={Ganji, Darshan C. and Ashfaq, Saad and Saboori, Ehsan and Sah, Sudhakar and Mitra, Saptarshi and AskariHemmat, MohammadHossein and Hoffman, Alexander and Hassanien, Ahmed and Léonardon, Mathieu},
 title={DeepGEMM: Accelerated Ultra Low-Precision Inference on CPU Architectures using Lookup Tables},
 booktitle={Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern Recognition Workshops}, year={2023},
 url={https://openaccess.thecvf.com/content/CVPR2023W/ECV/papers/Ganji_DeepGEMM_Accelerated_Ultra_Low-Precision_Inference_on_CPU_Architectures_Using_Lookup_CVPRW_2023_paper.pdf}
}

@inproceedings{won2022ulppack,
 author={Won, Jaeyeon and Si, Jeyeon and Son, Sam and Ham, Tae Jun and Lee, Jae W.},
 title={ULPPACK: Fast Sub-8-bit Matrix Multiply on Commodity SIMD Hardware},
 booktitle={Proceedings of Machine Learning and Systems}, volume={4}, year={2022},
 url={https://proceedings.mlsys.org/paper_files/paper/2022/hash/e09d45e14e9ece7142217550ddd3c4d0-Abstract.html}
}

@inproceedings{cowan2020quantized,
 author={Cowan, Meghan and Moreau, Thierry and Chen, Tianqi and Bornholt, James and Ceze, Luis},
 title={Automatic Generation of High-Performance Quantized Machine Learning Kernels},
 booktitle={Proceedings of the 18th ACM/IEEE International Symposium on Code Generation and Optimization},
 pages={305--316}, year={2020}, doi={10.1145/3368826.3377912}, url={https://jamesbornholt.com/papers/quantized-cgo20.pdf}
}

@inproceedings{wang2024ladder,
 author={Wang, Lei and Ma, Lingxiao and Cao, Shijie and Zhang, Quanlu and Xue, Jilong and Shi, Yining and Zheng, Ningxin and Miao, Ziming and Yang, Fan and Cao, Ting and Yang, Yuqing and Yang, Mao},
 title={Ladder: Enabling Efficient Low-Precision Deep Learning Computing through Hardware-aware Tensor Transformation},
 booktitle={18th USENIX Symposium on Operating Systems Design and Implementation}, pages={307--323}, year={2024},
 url={https://www.usenix.org/conference/osdi24/presentation/wang-lei}
}

@inproceedings{park2024lutgemm,
 author={Park, Gunho and Park, Baeseong and Kim, Minsub and Lee, Sungjae and Kim, Jeonghoon and Kwon, Beomseok and Kwon, Se Jung and Kim, Byeongwook and Lee, Youngjoo and Lee, Dongsoo},
 title={LUT-GEMM: Quantized Matrix Multiplication based on LUTs for Efficient Inference in Large-Scale Generative Language Models},
 booktitle={International Conference on Learning Representations}, year={2024}, eprint={2206.09557}, archivePrefix={arXiv}, url={https://arxiv.org/html/2206.09557v4}
}

@misc{oh2025tsar,
 author={Oh, Hyunwoo and Nam, KyungIn and Bhattacharjya, Rajat and Chen, Hanning and Das, Tamoghno and Yun, Sanggeon and Jang, Suyeon and Ding, Andrew and Dutt, Nikil and Imani, Mohsen},
 title={T-SAR: A Full-Stack Co-design for CPU-Only Ternary LLM Inference via In-Place SIMD ALU Reorganization},
 year={2025}, eprint={2511.13676}, archivePrefix={arXiv}, primaryClass={cs.AR}, url={https://arxiv.org/html/2511.13676v1}
}

@misc{google2019ruy,
 author={{Google LLC} and {ruy contributors}}, title={The ruy matrix multiplication library}, year={2019},
 howpublished={Open-source software}, url={https://github.com/google/ruy}, note={Apache-2.0; ARM64 in-order and baseline-NEON kernels, accessed 2026-11-03}
}

@misc{jacob2017gemmlowp,
 author={Jacob, Benoit and {Google} and Mansell, David and {gemmlowp contributors}},
 title={gemmlowp: a small self-contained low-precision GEMM library}, year={2017}, howpublished={Open-source software},
 url={https://github.com/google/gemmlowp}, note={Apache-2.0; A53 scheduling commentary at commit 36212ad3651871bc3e9a599f1a6d5324778aea25}
}

@misc{dukhan2019xnnpack,
 author={Dukhan, Marat and {XNNPACK contributors}}, title={XNNPACK}, year={2019}, howpublished={Open-source software},
 url={https://github.com/google/XNNPACK}, note={BSD-3-Clause; official Raspberry Pi benchmark table dated 2022-02-08, accessed 2026-11-03}
}

@misc{arm2024kleidiai,
 author={{Arm Limited} and {KleidiAI contributors}}, title={KleidiAI}, year={2024}, howpublished={Open-source microkernel library},
 url={https://github.com/ARM-software/kleidiai/blob/main/README.md}, note={Apache-2.0; ISA requirements are variant-specific, accessed 2026-11-03}
}

@misc{ankk2026gather,
 author={{Ankk98}}, title={Feature Request: skip redundant recurrent-state gather when n_rs == 1 and n_seqs == 1},
 year={2026}, howpublished={ggml-org/llama.cpp issue 28841}, url={https://github.com/ggml-org/llama.cpp/issues/28841},
 note={Opened 2026-09-13; open when inspected 2026-11-03; proposal, not measured implementation}
}

@misc{natemacfadden2026rollback,
 author={{natemacfadden} and {llama.cpp maintainers}},
 title={Eval bug: llama_memory_seq_rm returns true but does not restore the recurrent state when rolling back entire last decode},
 year={2026}, howpublished={ggml-org/llama.cpp issue 26695}, url={https://github.com/ggml-org/llama.cpp/issues/26695},
 note={Closed issue; reproducible report for b10298, not an A35 measurement}
}

@inproceedings{chen2018groupreduce,
 author={Chen, Patrick H. and Si, Si and Li, Yang and Chelba, Ciprian and Hsieh, Cho-Jui},
 title={GroupReduce: Block-Wise Low-Rank Approximation for Neural Language Model Shrinking},
 booktitle={Advances in Neural Information Processing Systems}, volume={31}, year={2018},
 url={https://proceedings.neurips.cc/paper_files/paper/2018/hash/a2b8a85a29b2d64ad6f47275bf1360c6-Abstract.html}
}

@misc{duan2026signedkv,
 author={Duan, Ziang and Wu, Jiajun and Chen, Zetian and Song, Hao and Deng, Yanwen and Shen, Zixuan and Xie, Nuobei and Wu, Simo and Wang, Bolun and Zhou, Peng and Wang, Chao},
 title={Unified Lookup-Table Inference with Signed-Digit K/V Caches for Ternary LLMs}, year={2026},
 eprint={2608.03229}, archivePrefix={arXiv}, primaryClass={cs.AR}, url={https://arxiv.org/html/2608.03229v1}
}

@misc{compilade2024ternary,
 author={{compilade} and {llama.cpp contributors}}, title={ggml-quants: ternary packing for TriLMs and BitNet b1.58},
 year={2024}, howpublished={ggml-org/llama.cpp pull request 8151}, url={https://github.com/ggml-org/llama.cpp/pull/8151},
 note={Merged 2024-09-06; MIT; microbenchmark bandwidth is float32-equivalent unless labeled packed}
}

@misc{prism2026q1,
 author={{khosravipasha} and {PrismML} and {llama.cpp contributors}}, title={ggml: add Q1_0 1-bit quantization support (CPU)},
 year={2026}, howpublished={ggml-org/llama.cpp pull request 21273}, url={https://github.com/ggml-org/llama.cpp/pull/21273}, note={Merged 2026-04-06; final Q1_0 group size 128; MIT}
}

@misc{prism2026q2,
 author={{khosravipasha} and {PrismML} and {llama.cpp contributors}}, title={ggml: add Q2_0 quantization support (CPU)},
 year={2026}, howpublished={ggml-org/llama.cpp pull request 24448}, url={https://github.com/ggml-org/llama.cpp/pull/24448}, note={Merged 2026-07-07; group size 64, unlike PQ2_0; MIT}
}

@misc{pl7522026repack,
 author={{pl752} and {llama.cpp contributors}}, title={ggml-cpu: ARM Repack kernels for Q1_0}, year={2026},
 howpublished={ggml-org/llama.cpp pull request 23492}, url={https://github.com/ggml-org/llama.cpp/pull/23492}, note={Merged 2026-09-21; dotprod/i8mm paths, not baseline ARMv8.0; MIT}
}

@misc{karusrus2026ptq,
 author={{karusrus} and {PrismML contributors}}, title={arm: NEON + i8mm vec_dot for PTQ1_0}, year={2026},
 howpublished={PrismML-Eng/llama.cpp pull request 290}, url={https://github.com/PrismML-Eng/llama.cpp/pull/290}, note={Merged 2026-10-07; MIT}
}

@misc{danblon2026hadamard,
 author={Danblon, Quentin}, title={ggml: add PQ2_0 and PTQ1_0 ternary types; llama: apply Hadamard-folded weights},
 year={2026}, howpublished={ggml-org/llama.cpp pull request 29077}, url={https://github.com/ggml-org/llama.cpp/pull/29077},
 note={Closed without merge; accessed 2026-11-03; MIT proposed code}
}

@misc{ansar2026tqrepack,
 author={{ansarzeinulla}}, title={Feature Request: CPU ARM i8mm 8x8 blocked GEMM/GEMV paths for TQ1_0 and TQ2_0},
 year={2026}, howpublished={ggml-org/llama.cpp issue 27276}, url={https://github.com/ggml-org/llama.cpp/issues/27276}, note={Closed stale feature request; not an implemented or benchmarked optimization}
}

@misc{pl7522026q1dot,
 author={{pl752} and {llama.cpp contributors}}, title={ggml-cpu: Optimized Arm NEON cpu q1_0 dot with plain NEON, DP and I8MM},
 year={2026}, howpublished={ggml-org/llama.cpp pull request 23358}, url={https://github.com/ggml-org/llama.cpp/pull/23358}, note={Open when inspected 2026-11-03; proposed code MIT; includes plain-NEON XOR/subtract path}
}

@inproceedings{liu2023dejavu,
  title     = {Deja Vu: Contextual Sparsity for Efficient {LLM}s at Inference Time},
  author    = {Liu, Zichang and Wang, Jue and Dao, Tri and Zhou, Tianyi and
               Yuan, Binhang and Song, Zhao and Shrivastava, Anshumali and
               Zhang, Ce and Tian, Yuandong and Ré, Christopher and Chen, Beidi},
  booktitle = {Proceedings of the 40th International Conference on Machine Learning},
  series    = {Proceedings of Machine Learning Research},
  volume    = {202},
  pages     = {22137--22176},
  publisher = {PMLR},
  year      = {2023},
  url       = {https://proceedings.mlr.press/v202/liu23am.html}
}

@inproceedings{song2024powerinfer,
  title     = {PowerInfer: Fast Large Language Model Serving with a Consumer-grade GPU},
  author    = {Song, Yixin and Mi, Zeyu and Xie, Haotong and Chen, Haibo},
  booktitle = {Proceedings of the ACM SIGOPS 30th Symposium on Operating Systems Principles},
  year      = {2024},
  doi       = {10.1145/3694715.3695964},
  url       = {https://ipads.sjtu.edu.cn/_media/publications/song-sosp24.pdf}
}

@misc{xue2024powerinfer2,
  title         = {PowerInfer-2: Fast Large Language Model Inference on a Smartphone},
  author        = {Xue, Zhenliang and Song, Yixin and Mi, Zeyu and
                   Zheng, Xinrui and Xia, Yubin and Chen, Haibo},
  year          = {2024},
  eprint        = {2406.06282},
  archivePrefix = {arXiv},
  primaryClass  = {cs.LG},
  note          = {Version 3},
  url           = {https://arxiv.org/abs/2406.06282v3}
}

@misc{song2024turbosparse,
  title         = {Turbo Sparse: Achieving {LLM} {SOTA} Performance with Minimal Activated Parameters},
  author        = {Song, Yixin and Xie, Haotong and Zhang, Zhengyan and
                   Wen, Bo and Ma, Li and Mi, Zeyu and Chen, Haibo},
  year          = {2024},
  eprint        = {2406.05955},
  archivePrefix = {arXiv},
  primaryClass  = {cs.LG},
  url           = {https://arxiv.org/abs/2406.05955}
}

@inproceedings{lee2024cats,
  title     = {{CATS}: Contextually-Aware Thresholding for Sparsity in Large Language Models},
  author    = {Lee, Donghyun and Lee, Je-Yong and Zhang, Genghan and
               Tiwari, Mo and Mirhoseini, Azalia},
  booktitle = {Conference on Language Modeling},
  year      = {2024},
  note      = {Author order follows arXiv version 4},
  url       = {https://arxiv.org/abs/2404.08763v4}
}

@inproceedings{liu2025teal,
  title     = {Training-Free Activation Sparsity in Large Language Models},
  author    = {Liu, James and Ponnusamy, Pragaash and Cai, Tianle and
               Guo, Han and Kim, Yoon and Athiwaratkun, Ben},
  booktitle = {International Conference on Learning Representations},
  year      = {2025},
  url       = {https://arxiv.org/abs/2408.14690}
}

@inproceedings{mirzadeh2024relu,
  title     = {{ReLU} Strikes Back: Exploiting Activation Sparsity in Large Language Models},
  author    = {Mirzadeh, Iman and Alizadeh, Keivan and Mehta, Sachin and
               Del Mundo, Carlo C and Tuzel, Oncel and Samei, Golnoosh and
               Rastegari, Mohammad and Farajtabar, Mehrdad},
  booktitle = {International Conference on Learning Representations},
  year      = {2024},
  url       = {https://proceedings.iclr.cc/paper_files/paper/2024/file/6cf669c222ad13f60d503736fb2bd15b-Paper-Conference.pdf}
}

@inproceedings{zhao2025frspec,
  title = {{FR}-Spec: Accelerating Large-Vocabulary Language Models via Frequency-Ranked Speculative Sampling},
  author = {Zhao, Weilin and Pan, Tengyu and Han, Xu and Zhang, Yudi and Sun, Ao and Huang, Yuxiang and Zhang, Kaihuo and Zhao, Weilun and Li, Yuxuan and Zhou, Jie and Zhou, Hao and Wang, Jianyong and Liu, Zhiyuan and Sun, Maosong},
  booktitle = {Proceedings of the 63rd Annual Meeting of the Association for Computational Linguistics},
  pages = {3909--3921},
  year = {2025},
  doi = {10.18653/v1/2025.acl-long.198},
  url = {https://aclanthology.org/2025.acl-long.198/}
}

@inproceedings{nozaki2025vocabulary,
  title = {Efficient Vocabulary Reduction for Small Language Models},
  author = {Nozaki, Yuta and Nakashima, Dai and Sato, Ryo and Asaba, Naoki and Kawamura, Shintaro},
  booktitle = {Proceedings of the 31st International Conference on Computational Linguistics: Industry Track},
  pages = {771--783},
  year = {2025},
  url = {https://aclanthology.org/2025.coling-industry.64/}
}

@inproceedings{baharav2024adaptive,
  title = {Adaptive Sampling for Efficient Softmax Approximation},
  author = {Baharav, Tavor Z. and Kang, Ryan and Sullivan, Colin and Tiwari, Mo and Luxenberg, Eric and Tse, David and Pilanci, Mert},
  booktitle = {Advances in Neural Information Processing Systems},
  volume = {37},
  year = {2024},
  url = {https://proceedings.neurips.cc/paper_files/paper/2024/hash/d52dbd66219dc4e432e0bd4f9c25c4c3-Abstract-Conference.html}
}

@inproceedings{leviathan2023speculative,
  title = {Fast Inference from Transformers via Speculative Decoding},
  author = {Leviathan, Yaniv and Kalman, Matan and Matias, Yossi},
  booktitle = {Proceedings of the 40th International Conference on Machine Learning},
  series = {Proceedings of Machine Learning Research},
  volume = {202},
  pages = {19274--19286},
  year = {2023},
  url = {https://proceedings.mlr.press/v202/leviathan23a.html}
}

@misc{korat2024uag,
  title = {Universal Assisted Generation: Faster Decoding with Any Assistant Model},
  author = {Korat, Daniel and Pereg, Oren and Berchansky, Moshe and Mamou, Jonathan and Gante, Joao and Tunstall, Lewis and Timor, Nadav and Wasserblat, Moshe},
  howpublished = {Hugging Face blog},
  month = oct,
  year = {2024},
  url = {https://huggingface.co/blog/universal_assisted_generation}
}

@inproceedings{elhoushi2024layerskip,
  title = {{LayerSkip}: Enabling Early Exit Inference and Self-Speculative Decoding},
  author = {Elhoushi, Mostafa and Shrivastava, Akshat and Liskovich, Diana and Hosmer, Basil and Wasti, Bram and Lai, Liangzhen and Mahmoud, Anas and Acun, Bilge and Agarwal, Saurabh and Roman, Ahmed and Aly, Ahmed and Chen, Beidi and Wu, Carole-Jean},
  booktitle = {Proceedings of the 62nd Annual Meeting of the Association for Computational Linguistics},
  pages = {12622--12642},
  year = {2024},
  doi = {10.18653/v1/2024.acl-long.681},
  url = {https://aclanthology.org/2024.acl-long.681/}
}

@inproceedings{zhang2024draft,
  title = {Draft \& Verify: Lossless Large Language Model Acceleration via Self-Speculative Decoding},
  author = {Zhang, Jun and Wang, Jue and Li, Huan and Shou, Lidan and Chen, Ke and Chen, Gang and Mehrotra, Sharad},
  booktitle = {Proceedings of the 62nd Annual Meeting of the Association for Computational Linguistics},
  pages = {11263--11282},
  year = {2024},
  url = {https://aclanthology.org/2024.acl-long.607/}
}

@inproceedings{fu2024lookahead,
  title = {Break the Sequential Dependency of {LLM} Inference Using Lookahead Decoding},
  author = {Fu, Yichao and Bailis, Peter and Stoica, Ion and Zhang, Hao},
  booktitle = {Proceedings of the 41st International Conference on Machine Learning},
  series = {Proceedings of Machine Learning Research},
  volume = {235},
  pages = {14060--14079},
  year = {2024},
  url = {https://proceedings.mlr.press/v235/fu24a.html}
}

@misc{saxena2023prompt,
  title = {Prompt Lookup Decoding},
  author = {Saxena, Apoorv},
  year = {2023},
  month = nov,
  howpublished = {Software repository},
  url = {https://github.com/apoorvumang/prompt-lookup-decoding}
}

@misc{benallal2025smollm2,
  title = {{SmolLM2}: When Smol Goes Big -- Data-Centric Training of a Small Language Model},
  author = {Ben Allal, Loubna and Lozhkov, Anton and Bakouch, Elie and Martín Blázquez, Gabriel and Penedo, Guilherme and Tunstall, Lewis and Marafioti, Andrés and Kydlíček, Hynek and Piqueres Lajarín, Agustín and Srivastav, Vaibhav and Lochner, Joshua and Fahlgren, Caleb and Nguyen, Xuan-Son and Fourrier, Clémentine and Burtenshaw, Ben and Larcher, Hugo and Zhao, Haojun and Zakka, Cyril and Morlon, Mathieu and Raffel, Colin and von Werra, Leandro and Wolf, Thomas},
  year = {2025},
  eprint = {2502.02737},
  archivePrefix = {arXiv},
  primaryClass = {cs.CL},
  url = {https://arxiv.org/abs/2502.02737}
}

@misc{llamacpp,
  author = {Gerganov, Georgi and {ggml authors}},
  title = {{llama.cpp}: {LLM} inference in {C/C++}},
  year = {2023},
  howpublished = {\url{https://github.com/ggml-org/llama.cpp}},
  note = {Open-source software; server documentation and PR 16391}
}

@inproceedings{yao2025cacheblend,
  author = {Yao, Jiayi and Li, Hanchen and Liu, Yuhan and Ray, Siddhant
    and Cheng, Yihua and Zhang, Qizheng and Du, Kuntai and Lu, Shan
    and Jiang, Junchen},
  title = {{CacheBlend}: Fast Large Language Model Serving for {RAG}
    with Cached Knowledge Fusion},
  booktitle = {Proceedings of the Twentieth European Conference on Computer Systems},
  pages = {94--109},
  year = {2025},
  doi = {10.1145/3689031.3696098},
  url = {https://arxiv.org/abs/2405.16444}
}

@inproceedings{zhang2026core,
  author = {Zhang, Zongpu and Dash, Pranab and Xu, Qiang and Hu, Y. Charlie
    and Li, Jian and Guan, Haibing},
  title = {Rethinking {DVFS} for Mobile {LLMs}: Unified Energy-Aware
    Scheduling with {CORE}},
  booktitle = {Proceedings of Machine Learning and Systems},
  volume = {8},
  pages = {186--198},
  year = {2026},
  url = {https://proceedings.mlsys.org/paper_files/paper/2026/file/136b9a13861308c8948cd308ccd02658-Paper-Conference.pdf}
}

@inproceedings{yang2026pelm,
  author = {Yang, Weisi and Xia, Stephen},
  title = {{PELM}: Power Efficient On-Device {LLM} Inference with
    Speculative Decoding and Dynamic Voltage Frequency Scaling},
  booktitle = {Proceedings of the 2026 ACM/IEEE International Conference
    on Embedded Artificial Intelligence and Sensing Systems},
  pages = {438--451},
  year = {2026},
  doi = {10.1145/3774906.3802783},
  url = {https://arxiv.org/abs/2609.09662}
}

@article{xiao2025pockets,
  author = {Xiao, Jie and Huang, Qianyi and Chen, Xu and Tian, Chen},
  title = {Understanding Large Language Models in Your Pockets:
    Performance Study on {COTS} Mobile Devices},
  journal = {arXiv preprint arXiv:2410.03613},
  year = {2025},
  url = {https://arxiv.org/abs/2410.03613},
  note = {Version 3}
}

@inproceedings{xu2025llmnpu,
  author = {Xu, Daliang and Zhang, Hao and Yang, Liming and Liu, Ruiqi
    and Huang, Gang and Xu, Mengwei and Liu, Xuanzhe},
  title = {Fast On-device {LLM} Inference with {NPUs}},
  booktitle = {Proceedings of the 30th ACM International Conference on
    Architectural Support for Programming Languages and Operating Systems,
    Volume 1},
  year = {2025},
  doi = {10.1145/3669940.3707239},
  url = {https://arxiv.org/abs/2407.05858}
}

@misc{wei2024tmac,
 author={Wei, Jianyu and Cao, Shijie and Cao, Ting and Ma, Lingxiao and Wang, Lei and Zhang, Yanyong and Yang, Mao},
 title={T-MAC: CPU Renaissance via Table Lookup for Low-Bit LLM Deployment on Edge},
 year={2024}, eprint={2407.00088}, archivePrefix={arXiv}, url={https://arxiv.org/abs/2407.00088}
}

@misc{wang2025bitnetcpp,
 author={Wang, Jinheng and Zhou, Hansong and Song, Ting and Cao, Shijie and Xia, Yan and Cao, Ting and Wei, Jianyu and Ma, Shuming and Wang, Hongyu and Wei, Furu},
 title={Bitnet.cpp: Efficient Edge Inference for Ternary LLMs},
 year={2025}, eprint={2502.11880}, archivePrefix={arXiv}, url={https://arxiv.org/abs/2502.11880}
}

@inproceedings{jacob2018integer,
 author={Jacob, Benoit and Kligys, Skirmantas and Chen, Bo and Zhu, Menglong and Tang, Matthew and Howard, Andrew and Adam, Hartwig and Kalenichenko, Dmitry},
 title={Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference},
 booktitle={Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition},
 year={2018}, pages={2704--2713},
 url={https://openaccess.thecvf.com/content_cvpr_2018/html/Jacob_Quantization_and_Training_CVPR_2018_paper.html}
}

@inproceedings{gloeckle2024mtp,
 author={Gloeckle, Fabian and Youbi Idrissi, Badr and Roziere, Baptiste and Lopez-Paz, David and Synnaeve, Gabriel},
 title={Better \& Faster Large Language Models via Multi-token Prediction},
 booktitle={Proceedings of the 41st International Conference on Machine Learning},
 volume={235}, pages={15706--15734}, year={2024}, url={https://proceedings.mlr.press/v235/gloeckle24a.html}
}

@inproceedings{cai2024medusa,
 author={Cai, Tianle and Li, Yuhong and Geng, Zhengyang and Peng, Hongwu and Lee, Jason D. and Chen, Deming and Dao, Tri},
 title={Medusa: Simple LLM Inference Acceleration Framework with Multiple Decoding Heads},
 booktitle={Proceedings of the 41st International Conference on Machine Learning},
 volume={235}, pages={5209--5235}, year={2024}, url={https://proceedings.mlr.press/v235/cai24b.html}
}

@inproceedings{li2024eagle,
 author={Li, Yuhui and Wei, Fangyun and Zhang, Chao and Zhang, Hongyang},
 title={EAGLE: Speculative Sampling Requires Rethinking Feature Uncertainty},
 booktitle={Proceedings of the 41st International Conference on Machine Learning},
 volume={235}, pages={28935--28948}, year={2024}, url={https://proceedings.mlr.press/v235/li24bt.html}
}

@misc{llvm2026a53,
 author={{LLVM Project contributors}}, title={Cortex-A53 Scheduling Definitions},
 year={2026}, howpublished={LLVM source},
 url={https://raw.githubusercontent.com/llvm/llvm-project/main/llvm/lib/Target/AArch64/AArch64SchedA53.td},
 note={Inspected 2026-11-03; Apache-2.0 WITH LLVM-exception}
}

@misc{llamacpp16391,
 author={{Georgi Gerganov (ggerganov)} and {llama.cpp contributors}}, title={server : host-memory prompt caching},
 year={2025}, howpublished={llama.cpp pull request 16391},
 url={https://github.com/ggml-org/llama.cpp/pull/16391}
}

@misc{llamacpp24785,
 author={{Moltes94} and {llama.cpp contributors}}, title={server: add recurrent state shrink/expand for prompt cache (#22746)},
 year={2026}, howpublished={llama.cpp pull request 24785},
 url={https://github.com/ggml-org/llama.cpp/pull/24785}
}

@misc{llamacpp21099,
 author={{hanxiao} and {llama.cpp contributors}}, title={server: fix prompt cache reuse for hybrid/recurrent models},
 year={2026}, howpublished={llama.cpp pull request 21099},
 url={https://github.com/ggml-org/llama.cpp/pull/21099}
}

@misc{llamacpp29918,
 author={{bcmyguest} and {llama.cpp contributors}}, title={server : add --cache-reuse-hybrid for recurrent/hybrid models},
 year={2026}, howpublished={llama.cpp pull request 29918},
 url={https://github.com/ggml-org/llama.cpp/pull/29918}
}
```
