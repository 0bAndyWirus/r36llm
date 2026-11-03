#include "ggml.h"
#include "ggml-cpu.h"
#include <cstdio>
#include <cstring>
#include <vector>
#include <cstdint>
static uint32_t rng=0x91e10da5;
static float next_float() { rng ^= rng<<13; rng ^= rng>>17; rng ^= rng<<5; return ((int)(rng%201)-100)*0.001f; }
static void fill(ggml_tensor *t) { float *p=(float *)t->data; for (int64_t i=0;i<ggml_nelements(t);++i) p[i]=next_float(); }
int main() {
 int cases=0;
 for (int dim : {16,64,128}) for (int threads : {1,4}) for (int row : {0,1,2}) for (bool raw : {false,true}) for (bool zero : {false,true}) {
  const int hk=dim==128?16:4, hv=hk*3;
  const int64_t d=(int64_t)dim*dim*hv;
  ggml_init_params ip={64*1024*1024,nullptr,false};
  auto *ctx=ggml_init(ip);
  auto *q=ggml_new_tensor_4d(ctx,GGML_TYPE_F32,dim,hk,1,1);
  auto *k=ggml_new_tensor_4d(ctx,GGML_TYPE_F32,dim,hk,1,1);
  auto *v=ggml_new_tensor_4d(ctx,GGML_TYPE_F32,dim,hv,1,1);
  auto *g=ggml_new_tensor_4d(ctx,GGML_TYPE_F32,1,hv,1,1);
  auto *b=ggml_new_tensor_4d(ctx,GGML_TYPE_F32,1,hv,1,1);
  auto *cache=ggml_new_tensor_2d(ctx,GGML_TYPE_F32,d,3);
  auto *rows=ggml_new_tensor_1d(ctx,GGML_TYPE_I32,1);
  for (auto *t : {q,k,v,g,b,cache}) fill(t);
  *(int32_t *)rows->data=row;
  if (zero) std::memset(cache->data, 0, ggml_nbytes(cache));
  auto *state=ggml_reshape_4d(ctx,ggml_get_rows(ctx,cache,rows),dim,dim,hv,1);
  auto *ref=ggml_gated_delta_net(ctx,q,k,v,g,b,state,1);
  auto *indexed=ggml_gated_delta_net_rows(ctx,q,k,v,g,b,cache,rows,1);
  if (raw) {
   auto *bias=ggml_new_tensor_1d(ctx,GGML_TYPE_F32,hv);
   auto *a=ggml_new_tensor_1d(ctx,GGML_TYPE_F32,hv);
   fill(bias); fill(a);
   ggml_gated_delta_net_set_raw_gates(ref,bias,a);
   ggml_gated_delta_net_set_raw_gates(indexed,bias,a);
  }
  auto *gr=ggml_new_graph(ctx), *gi=ggml_new_graph(ctx);
  ggml_build_forward_expand(gr,ref); ggml_build_forward_expand(gi,indexed);
  if (ggml_graph_compute_with_ctx(ctx,gr,threads)!=GGML_STATUS_SUCCESS || ggml_graph_compute_with_ctx(ctx,gi,threads)!=GGML_STATUS_SUCCESS) return 2;
  if (ggml_nbytes(ref)!=ggml_nbytes(indexed) || std::memcmp(ref->data,indexed->data,ggml_nbytes(ref))) {
   std::fprintf(stderr,"FAIL state rows dim=%d threads=%d row=%d raw=%d\n",dim,threads,row,raw); return 1;
  }
  ++cases; ggml_free(ctx);
 }
 std::printf("PASS indexed-state cases=%d full_output_and_state_bit_identical max_abs_error=0\n",cases);
}
