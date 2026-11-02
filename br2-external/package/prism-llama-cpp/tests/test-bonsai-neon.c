#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define GGML_COMMON_DECL_C
#include "ggml-common.h"
#include "ggml-cpu/quants.h"

#define MAX_BLOCKS 257
static uint32_t seed;
#define TRIALS 32

typedef void (*dot_fn)(int, float *, size_t, const void *, size_t, const void *, size_t, int);
struct kernel { const char *name; dot_fn neon, generic; int kind, q8k; };
static const struct kernel kernels[] = {
    {"q1_0_q8_0", ggml_vec_dot_q1_0_q8_0, ggml_vec_dot_q1_0_q8_0_generic, 0, 0},
    {"pq2_0_q8_0", ggml_vec_dot_pq2_0_q8_0, ggml_vec_dot_pq2_0_q8_0_generic, 1, 0},
    {"pq2_0_q8_K", ggml_vec_dot_pq2_0_q8_K, ggml_vec_dot_pq2_0_q8_K_generic, 1, 1},
    {"ptq1_0_q8_0", ggml_vec_dot_ptq1_0_q8_0, ggml_vec_dot_ptq1_0_q8_0_generic, 2, 0},
};
static block_q1_0 q1[MAX_BLOCKS];
static block_pq2_0 pq[MAX_BLOCKS];
static block_ptq1_0 pt[MAX_BLOCKS];
static block_q8_0 q8[MAX_BLOCKS * 4];
static block_q8_K q8k[(MAX_BLOCKS + 1) / 2];
static uint32_t rng;
static uint64_t cases;

static uint32_t random_u32(void) {
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
}
static void random_bytes(void *p, size_t n) {
    uint8_t *b = p;
    for (size_t i = 0; i < n; ++i) b[i] = (uint8_t) random_u32();
}
/* Every finite half exponent, including subnormals, with both signs. */
static uint16_t random_half(void) {
    uint32_t r = random_u32();
    return (uint16_t) ((r & 0x8000) | (((r >> 16) % 31) << 10) | (r & 1023));
}
static void prepare(int blocks, int pattern, int unit, int isolated) {
    for (int i = 0; i < blocks; ++i) {
        random_bytes(q1[i].qs, sizeof(q1[i].qs));
        random_bytes(pq[i].qs, sizeof(pq[i].qs));
        random_bytes(pt[i].qs, sizeof(pt[i].qs));
        random_bytes(pt[i].qh, sizeof(pt[i].qh));
        if (pattern >= 0) {
            memset(q1[i].qs, pattern, sizeof(q1[i].qs));
            memset(pq[i].qs, pattern, sizeof(pq[i].qs));
            memset(pt[i].qs, pattern, sizeof(pt[i].qs));
            memset(pt[i].qh, pattern, sizeof(pt[i].qh));
        }
        q1[i].d = unit ? 0x3c00 : random_half();
        pq[i].d = unit ? 0x3c00 : random_half();
        pt[i].d = unit ? 0x3c00 : random_half();
    }
    for (int i = 0; i < blocks * 4; ++i) {
        q8[i].d = unit ? 0x3c00 : random_half();
        random_bytes(q8[i].qs, sizeof(q8[i].qs));
        if (pattern == 0 || pattern == 127 || pattern == 128 || pattern == 255) memset(q8[i].qs, pattern, sizeof(q8[i].qs));
        if (isolated >= 0 && i % 4 != isolated) memset(q8[i].qs, 0, sizeof(q8[i].qs));
    }
    for (int i = 0; i < (blocks + 1) / 2; ++i) {
        q8k[i].d = unit ? 1.0f : (float) (1 + (random_u32() & 0xffffff)) / 4194304.0f;
        random_bytes(q8k[i].qs, sizeof(q8k[i].qs));
        if (pattern == 0 || pattern == 127 || pattern == 128 || pattern == 255) memset(q8k[i].qs, pattern, sizeof(q8k[i].qs));
        if (isolated >= 0) for (int j = 0; j < 256; ++j)
            if ((j / 32) != isolated) q8k[i].qs[j] = 0;
        for (int j = 0; j < 16; ++j) {
            int sum = 0;
            for (int k = 0; k < 16; ++k) sum += q8k[i].qs[j * 16 + k];
            q8k[i].bsums[j] = (int16_t) sum;
        }
    }
}
static const void *weights(int kind) { return kind == 0 ? (const void *)q1 : kind == 1 ? (const void *)pq : (const void *)pt; }
static int trit(uint8_t byte, int power) {
    static const unsigned pow3[] = {1, 3, 9, 27, 81};
    return ((uint8_t)(byte * pow3[power]) * 3 >> 8) - 1;
}
/* Independent integer oracle for unit-scale tests, including invalid packed bytes. */
static int weight(int kind, int block, int index) {
    if (kind == 0) return ((q1[block].qs[index / 8] >> (index % 8)) & 1) ? 1 : -1;
    if (kind == 1) return ((pq[block].qs[index / 4] >> (2 * (index % 4))) & 3) - 1;
    if (index < 80) return trit(pt[block].qs[index % 16], index / 16);
    if (index < 120) return trit(pt[block].qs[16 + (index - 80) % 8], (index - 80) / 8);
    return trit(pt[block].qh[(index - 120) % 2], (index - 120) / 2);
}
static int integer_dot(const struct kernel *k, int blocks) {
    int sum = 0;
    for (int i = 0; i < blocks; ++i) for (int j = 0; j < 128; ++j) {
        int y = k->q8k ? q8k[i / 2].qs[(i % 2) * 128 + j] : q8[i * 4 + j / 32].qs[j % 32];
        sum += weight(k->kind, i, j) * y;
    }
    return sum;
}
static int compare(const struct kernel *k, int blocks, int unit, const char *mode, int detail, int trial) {
    float actual = -12345.0f, expected = -54321.0f;
    const void *y = k->q8k ? (const void *)q8k : (const void *)q8;
    k->generic(blocks * 128, &expected, 0, weights(k->kind), 0, y, 0, 1);
    k->neon(blocks * 128, &actual, 0, weights(k->kind), 0, y, 0, 1);
    ++cases;
    int oracle = unit ? integer_dot(k, blocks) : 0;
    if (memcmp(&actual, &expected, sizeof(actual)) || (unit && (expected != (float)oracle || actual != (float)oracle))) {
        uint32_t a, e; memcpy(&a, &actual, 4); memcpy(&e, &expected, 4);
        fprintf(stderr, "FAIL kernel=%s blocks=%d mode=%s detail=%d trial=%d seed=0x%08" PRIx32 " rng=0x%08" PRIx32 " actual=%a (0x%08" PRIx32 ") generic=%a (0x%08" PRIx32 ")", k->name, blocks, mode, detail, trial, seed, rng, actual, a, expected, e);
        if (unit) fprintf(stderr, " integer=%d", oracle);
        fputc('\n', stderr);
        return 1;
    }
    return 0;
}
static int run_tests(void) {
    static const int counts[] = {0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 257};
    for (size_t c = 0; c < sizeof(counts)/sizeof(counts[0]); ++c) {
        int n = counts[c];
        for (int t = 0; t < TRIALS; ++t) for (int unit = 0; unit <= 1; ++unit) {
            prepare(n, -1, unit, -1);
            for (size_t k = 0; k < sizeof(kernels)/sizeof(kernels[0]); ++k)
                if ((!kernels[k].q8k || n % 2 == 0) && compare(&kernels[k], n, unit, "random", unit, t)) return 1;
        }
    }
    /* Every packed byte value appears in every PTQ byte position, including qh. */
    for (int p = 0; p < 256; ++p) for (int isolation = -1; isolation < 8; ++isolation) {
        prepare(2, p, 1, isolation);
        for (size_t k = 0; k < sizeof(kernels)/sizeof(kernels[0]); ++k) {
            if (!kernels[k].q8k && isolation >= 4) continue;
            if (compare(&kernels[k], 2, 1, "packed-byte/isolation", p, isolation)) return 1;
        }
    }
    /* Cross maximal weight codes with both Q8 extrema to exercise widening. */
    for (int p = 0; p < 256; p += 85) for (int y = -128; y <= 127; y += 255) {
        prepare(MAX_BLOCKS, p, 1, -1);
        for (size_t i = 0; i < sizeof(q8) / sizeof(q8[0]); ++i)
            memset(q8[i].qs, (uint8_t)y, sizeof(q8[i].qs));
        for (size_t i = 0; i < sizeof(q8k) / sizeof(q8k[0]); ++i)
            memset(q8k[i].qs, (uint8_t)y, sizeof(q8k[i].qs));
        for (size_t k = 0; k < sizeof(kernels) / sizeof(kernels[0]); ++k) {
            const int n = kernels[k].q8k ? MAX_BLOCKS - 1 : MAX_BLOCKS;
            if (compare(&kernels[k], n, 1, "extrema", p, y)) return 1;
        }
    }
    printf("PASS cases=%" PRIu64 " seed=0x%08" PRIx32 " random_trials=%d max_abs_error=0 max_rel_error=0 (bit-identical)\n", cases, seed, TRIALS);
    return 0;
}
int main(void) {
    static const uint32_t seeds[] = {0x91e10da5, 1, 2, 3, 0x12345678, 0xdeadbeef, 0x80000000, 0xffffffff};
    for (size_t i = 0; i < sizeof(seeds) / sizeof(seeds[0]); ++i) {
        seed = rng = seeds[i];
        cases = 0;
        if (run_tests()) return 1;
    }
    return 0;
}
