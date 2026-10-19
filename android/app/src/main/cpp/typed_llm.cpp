// One-shot local inference for the voice-memo shaper.
//
// Dart calls typed_llm_run() on a background isolate: load the model (mmap),
// run one grammar-constrained, greedy completion, free everything. A memo is
// shaped once, so keeping the model resident between calls is not worth the
// memory it would hold.

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "llama.h"

namespace {

void silent_log(ggml_log_level, const char *, void *) {}

char *dup(const std::string &s) {
  char *out = static_cast<char *>(std::malloc(s.size() + 1));
  if (out) std::memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

struct Run {
  llama_model *model = nullptr;
  llama_context *ctx = nullptr;
  llama_sampler *grammar = nullptr;
  ~Run() {
    if (grammar) llama_sampler_free(grammar);
    if (ctx) llama_free(ctx);
    if (model) llama_model_free(model);
    llama_backend_free();
  }
};

}  // namespace

extern "C" {

// Returns the generated text (malloc'd; free with typed_llm_free), or a
// string starting with "ERR:" describing what failed.
__attribute__((visibility("default"))) char *typed_llm_run(
    const char *model_path, const char *prompt, const char *grammar,
    int max_tokens, int n_threads, int budget_ms) {
  // A hard wall-clock budget: the app shows the rules draft meanwhile and
  // must never be left "refining" forever on a slow device.
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::milliseconds(budget_ms);
  llama_log_set(silent_log, nullptr);
  llama_backend_init();
  Run run;

  llama_model_params mp = llama_model_default_params();
  mp.n_gpu_layers = 0;
  run.model = llama_model_load_from_file(model_path, mp);
  if (!run.model) return dup("ERR:load");
  const llama_vocab *vocab = llama_model_get_vocab(run.model);

  // Tokenise first so the context is sized to the prompt.
  const int len = static_cast<int>(std::strlen(prompt));
  std::vector<llama_token> tokens(len + 8);
  const int n = llama_tokenize(vocab, prompt, len, tokens.data(),
                               static_cast<int>(tokens.size()),
                               /*add_special=*/false, /*parse_special=*/true);
  if (n < 0) return dup("ERR:tokenize");
  tokens.resize(n);

  llama_context_params cp = llama_context_default_params();
  cp.n_ctx = static_cast<uint32_t>(n + max_tokens + 16);
  cp.n_batch = cp.n_ctx;
  cp.n_ubatch = 512;
  cp.n_threads = n_threads;
  cp.n_threads_batch = n_threads;
  cp.no_perf = true;
  run.ctx = llama_init_from_model(run.model, cp);
  if (!run.ctx) return dup("ERR:context");

  if (grammar && grammar[0]) {
    run.grammar = llama_sampler_init_grammar(vocab, grammar, "root");
    if (!run.grammar) return dup("ERR:grammar");
  }

  // Greedy decoding with the grammar checked lazily: take the top token, and
  // only when the grammar rejects it run the grammar over the whole
  // vocabulary (150k+ entries for Qwen). A trained model almost always
  // proposes a valid token, so this keeps grammar cost off nearly every step.
  const int n_vocab = llama_vocab_n_tokens(vocab);
  std::vector<llama_token_data> cand(n_vocab);

  std::string out;
  int rc = llama_decode(run.ctx, llama_batch_get_one(tokens.data(), n));
  for (int i = 0; rc == 0 && i < max_tokens; i++) {
    if (std::chrono::steady_clock::now() > deadline) return dup("ERR:timeout");
    const float *logits = llama_get_logits_ith(run.ctx, -1);
    llama_token tok = 0;
    for (int t = 1; t < n_vocab; t++) {
      if (logits[t] > logits[tok]) tok = t;
    }
    if (run.grammar) {
      llama_token_data one = {tok, logits[tok], 0.0f};
      llama_token_data_array single = {&one, 1, -1, false};
      llama_sampler_apply(run.grammar, &single);
      if (std::isinf(single.data[0].logit)) {
        for (int t = 0; t < n_vocab; t++) cand[t] = {t, logits[t], 0.0f};
        llama_token_data_array all = {cand.data(), cand.size(), -1, false};
        llama_sampler_apply(run.grammar, &all);
        size_t best = 0;
        for (size_t k = 1; k < all.size; k++) {
          if (all.data[k].logit > all.data[best].logit) best = k;
        }
        if (std::isinf(all.data[best].logit)) break;  // grammar complete
        tok = all.data[best].id;
      }
      llama_sampler_accept(run.grammar, tok);
    }
    if (llama_vocab_is_eog(vocab, tok)) break;
    char buf[256];
    const int k = llama_token_to_piece(vocab, tok, buf, sizeof buf, 0, false);
    if (k > 0) out.append(buf, k);
    rc = llama_decode(run.ctx, llama_batch_get_one(&tok, 1));
  }

  if (rc != 0) return dup("ERR:decode");
  return dup(out);
}

__attribute__((visibility("default"))) void typed_llm_free(char *p) {
  std::free(p);
}

}  // extern "C"
