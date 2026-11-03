/* Reuse the established packed-byte generator and independent integer oracle. */
#define main bonsai_single_row_main
#include "test-bonsai-neon.c"
#undef main

static block_ptq1_0 pt_rows[2][MAX_BLOCKS + 3];
static block_pq2_0 pq_rows[2][MAX_BLOCKS + 3];
static uint64_t row_cases;

static int compare_rows(int blocks, int unit, int pattern, int isolation, int extreme) {
    float actual_pt[4] = {-12345, 0, 0, -54321};
    float actual_pq[4] = {-12345, 0, 0, -54321};
    for (int row = 0; row < 2; ++row) {
        prepare(blocks, pattern < 0 ? -1 : ((pattern + row*37) & 255), unit, isolation);
        memcpy(pt_rows[row], pt, blocks*sizeof(pt[0]));
        memcpy(pq_rows[row], pq, blocks*sizeof(pq[0]));
    }
    if (extreme >= -128 && extreme <= 127) {
        for (int i = 0; i < blocks*4; ++i) memset(q8[i].qs, (uint8_t)extreme, sizeof(q8[i].qs));
        for (int i = 0; i < (blocks + 1)/2; ++i) {
            memset(q8k[i].qs, (uint8_t)extreme, sizeof(q8k[i].qs));
            for (int j = 0; j < 16; ++j) q8k[i].bsums[j] = 16*extreme;
        }
    }
    /* Keep nontrivial padding between the two rows to check byte-stride handling. */
    ggml_vec_dot_ptq1_0_q8_0_2rows(blocks*128, actual_pt + 1, pt_rows, sizeof(pt_rows[0]), q8);
    if (blocks % 2 == 0)
        ggml_vec_dot_pq2_0_q8_K_2rows(blocks*128, actual_pq + 1, pq_rows, sizeof(pq_rows[0]), q8k);
    if (actual_pt[0] != -12345 || actual_pt[3] != -54321 || actual_pq[0] != -12345 || actual_pq[3] != -54321) {
        fprintf(stderr, "FAIL output canary\n");
        return 1;
    }
    for (int row = 0; row < 2; ++row) {
        memcpy(pt, pt_rows[row], blocks*sizeof(pt[0]));
        memcpy(pq, pq_rows[row], blocks*sizeof(pq[0]));
        for (int kind = 0; kind < 2; ++kind) {
            if (kind && blocks % 2) continue;
            const struct kernel *k = &kernels[kind ? 2 : 3];
            float expected;
            k->generic(blocks*128, &expected, 0, weights(k->kind), 0, kind ? (void *)q8k : (void *)q8, 0, 1);
            float actual = kind ? actual_pq[row + 1] : actual_pt[row + 1];
            ++row_cases;
            if (memcmp(&expected, &actual, sizeof(float)) || (unit && actual != (float)integer_dot(k, blocks))) {
                fprintf(stderr, "FAIL rows kernel=%s row=%d blocks=%d unit=%d pattern=%d isolation=%d expected=%a actual=%a seed=0x%08" PRIx32 "\n", k->name, row, blocks, unit, pattern, isolation, expected, actual, seed);
                return 1;
            }
        }
    }
    return 0;
}

int main(void) {
    static const uint32_t seeds[] = {0x91e10da5, 1, 2, 3, 0x12345678, 0xdeadbeef, 0x80000000, 0xffffffff};
    static const int counts[] = {0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 48, 63, 64, 127, 128, 256, 257};
    for (size_t i = 0; i < sizeof(seeds)/sizeof(seeds[0]); ++i) {
        seed = rng = seeds[i];
        for (size_t c = 0; c < sizeof(counts)/sizeof(counts[0]); ++c)
            for (int t = 0; t < TRIALS; ++t)
                for (int unit = 0; unit <= 1; ++unit)
                    if (compare_rows(counts[c], unit, -1, -1, 129)) return 1;
        for (int pattern = 0; pattern < 256; ++pattern)
            for (int isolation = -1; isolation < 8; ++isolation)
                if (compare_rows(2, 1, pattern, isolation, 129)) return 1;
        for (int pattern = 0; pattern < 256; pattern += 85)
            for (int extreme = -128; extreme <= 127; extreme += 255)
                if (compare_rows(256, 1, pattern, -1, extreme)) return 1;
    }
    printf("PASS two-row cases=%" PRIu64 " max_abs_error=0 max_rel_error=0 (bit-identical)\n", row_cases);
    return 0;
}
