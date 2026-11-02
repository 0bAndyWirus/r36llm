#include "llama.h"
#include "ggml.h"
#include "gguf.h"
#include "ggml-cpu.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>

using Clock = std::chrono::steady_clock;
struct Record { const ggml_tensor * tensor; double ms; };
struct Timing {
    Clock::time_point start;
    std::vector<Record> records;
};
static bool callback(ggml_tensor * tensor, bool ask, void * data) {
    auto & timing = *static_cast<Timing *>(data);
    if (ask) {
        timing.start = Clock::now();
    } else {
        const auto end = Clock::now();
        timing.records.push_back({tensor, std::chrono::duration<double, std::milli>(end - timing.start).count()});
    }
    return true;
}
static void metadata(const char * model, const char * prefix) {
    char path[1024];
    std::snprintf(path, sizeof(path), "%s-weights.csv", prefix);
    FILE * out = std::fopen(path, "w");
    gguf_context * meta = gguf_init_from_file(model, {true, nullptr});
    if (!out || !meta) std::exit(2);
    std::fprintf(out, "tensor,type,ne0,ne1,ne2,ne3,bytes\n");
    for (int64_t i = 0; i < gguf_get_n_tensors(meta); ++i) {
        const auto * ne = gguf_get_tensor_ne(meta, i);
        std::fprintf(out, "%s,%s,%lld,%lld,%lld,%lld,%zu\n", gguf_get_tensor_name(meta, i),
            ggml_type_name(gguf_get_tensor_type(meta, i)), (long long)ne[0], (long long)ne[1],
            (long long)ne[2], (long long)ne[3], gguf_get_tensor_size(meta, i));
    }
    gguf_free(meta);
    std::fclose(out);
}
static void run_step(llama_context * ctx, Timing & timing, FILE * nodes, FILE * steps,
                     const char * mode, const char * phase, int trial, std::vector<llama_token> & tokens) {
    timing.records.clear();
    const auto start = Clock::now();
    const int result = llama_decode(ctx, llama_batch_get_one(tokens.data(), int(tokens.size())));
    llama_synchronize(ctx);
    const double ms = std::chrono::duration<double, std::milli>(Clock::now() - start).count();
    if (result != 0) { std::fprintf(stderr, "decode failed: %d\n", result); std::exit(3); }
    double sum = 0;
    for (size_t i = 0; i < timing.records.size(); ++i) {
        const auto & r = timing.records[i];
        const auto * t = r.tensor;
        const auto * w = t->src[0];
        sum += r.ms;
        if (nodes) std::fprintf(nodes, "%s,%s,%d,%zu,%s,%s,%.9f,%s,%s,%lld,%lld,%lld,%lld\n",
            mode, phase, trial, i, t->name, ggml_op_name(t->op), r.ms,
            w ? w->name : "", w ? ggml_type_name(w->type) : "",
            (long long)t->ne[0], (long long)t->ne[1], (long long)t->ne[2], (long long)t->ne[3]);
    }
    if (steps) {
        std::fprintf(steps, "%s,%s,%d,%zu,%.9f,%.9f,%zu\n", mode, phase, trial, tokens.size(), ms, sum, timing.records.size());
        std::fflush(steps);
    }
    if (nodes) std::fflush(nodes);
}
int main(int argc, char ** argv) {
    if (argc != 4) { std::fprintf(stderr, "usage: %s MODEL OUTPUT_PREFIX plain|profile\n", argv[0]); return 1; }
    metadata(argv[1], argv[2]);
    char path[1024];
    std::snprintf(path, sizeof(path), "%s-nodes.csv", argv[2]);
    FILE * nodes = std::fopen(path, "w");
    std::snprintf(path, sizeof(path), "%s-steps.csv", argv[2]);
    FILE * steps = std::fopen(path, "w");
    if (!nodes || !steps) return 2;
    std::fprintf(nodes, "mode,phase,trial,index,tensor,op,ms,src0,src0_type,ne0,ne1,ne2,ne3\n");
    std::fprintf(steps, "mode,phase,trial,tokens,wall_ms,node_ms,nodes\n");
    llama_backend_init();
    auto mp = llama_model_default_params();
    mp.n_gpu_layers = 0;
    llama_model * model = llama_model_load_from_file(argv[1], mp);
    if (!model) return 2;
    const auto * vocab = llama_model_get_vocab(model);
    const int n_vocab = llama_vocab_n_tokens(vocab);
    const int instrumented = std::string(argv[3]) == "profile" ? 1 : 0;
    {
        Timing timing;
        timing.records.reserve(8192);
        auto cp = llama_context_default_params();
        cp.n_ctx = 128; cp.n_batch = 128; cp.n_ubatch = 128;
        cp.n_threads = 4; cp.n_threads_batch = 4;
        cp.cb_eval = instrumented ? callback : nullptr;
        cp.cb_eval_user_data = &timing;
        llama_context * ctx = llama_init_from_model(model, cp);
        if (!ctx) return 2;
        auto pool_params = ggml_threadpool_params_default(4);
        auto * pool = ggml_threadpool_new(&pool_params);
        if (!pool) return 2;
        llama_attach_threadpool(ctx, pool, nullptr);
        const char * mode = instrumented ? "profile" : "plain";
        std::vector<llama_token> token(1, llama_vocab_get_add_bos(vocab) ? llama_vocab_bos(vocab) : 1);
        run_step(ctx, timing, nullptr, nullptr, mode, "warmup", 0, token);
        llama_memory_clear(llama_get_memory(ctx), false);
        for (int i = 0; i < 5; ++i) {
            token[0] = (1234 + i * 53) % n_vocab;
            run_step(ctx, timing, nodes, steps, mode, "decode", i, token);
        }
        std::vector<llama_token> prompt(8);
        for (int i = 0; i < 8; ++i) prompt[i] = (1234 + i * 53) % n_vocab;
        llama_memory_clear(llama_get_memory(ctx), false);
        run_step(ctx, timing, nullptr, nullptr, mode, "warmup_prompt", 0, prompt);
        for (int i = 0; i < 3; ++i) {
            llama_memory_clear(llama_get_memory(ctx), false);
            run_step(ctx, timing, nodes, steps, mode, "prompt8", i, prompt);
        }
        llama_detach_threadpool(ctx);
        ggml_threadpool_free(pool);
        llama_free(ctx);
    }
    llama_model_free(model);
    llama_backend_free();
    std::fclose(nodes); std::fclose(steps);
    return 0;
}
