#include <omp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec*1e-9; }
int main(void) {
 const size_t n = 64*1024*1024; const int reps = 32;
 unsigned char *a = malloc(n), *b = malloc(n);
 if (!a || !b) return 2;
 memset(a, 0x53, n); memset(b, 0x19, n);
 for (int threads=1; threads<=4; threads*=4) {
  double start=now();
  #pragma omp parallel num_threads(threads)
  {
   size_t offset = n*omp_get_thread_num()/threads;
   size_t bytes = n/threads;
   for (int i=0; i<reps; ++i) {
    memcpy(b+offset, a+offset, bytes);
    #pragma omp barrier
    memcpy(a+offset, b+offset, bytes);
    #pragma omp barrier
   }
  }
  double elapsed=now()-start;
  printf("copy threads=%d seconds=%.6f payload_GBps=%.6f read_plus_write_GBps=%.6f canary=%u\n",threads,elapsed,2.0*reps*n/elapsed/1e9,4.0*reps*n/elapsed/1e9,a[n-1]+b[n-1]);
 }
 free(a); free(b); return 0;
}
