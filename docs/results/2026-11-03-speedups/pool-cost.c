#include "ggml.h"
#include "ggml-cpu.h"
#include <time.h>
#include <stdio.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec*1e-9; }
int main(void) {
 struct ggml_threadpool_params p=ggml_threadpool_params_default(4);
 const int n=100000;
 double start=now();
 for (int i=0;i<n;++i) { struct ggml_threadpool *pool=ggml_threadpool_new(&p); if(!pool) return 2; ggml_threadpool_free(pool); }
 double elapsed=now()-start;
 printf("OpenMP disposable_pool pairs=%d seconds=%.9f microseconds_per_new_free=%.6f\n",n,elapsed,elapsed*1e6/n);
 return 0;
}
