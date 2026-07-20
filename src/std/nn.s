// ============================================
// S Language Neural Network Compatibility Layer
// ============================================
//
// `std.nn` keeps the historical GPT-facing API alive while delegating the
// actual layer implementations to `std.ai.nn`.
// ============================================

package std.nn

use std.ai.nn as AI
use std.ai.autograd as AG

type Module = AI.Module
type Linear = AI.Linear
type embedding = AI.embedding
type LayerNorm = AI.LayerNorm
type MultiHeadAttention = AI.MultiHeadAttention
type FeedForward = AI.FeedForward
type TransformerBlock = AI.TransformerBlock
type Dropout = AI.Dropout
type ReLU_Mod = AI.ReLU
type GELU_Mod = AI.GELU
type Sigmoid_Mod = AI.Sigmoid
type Softmax_Mod = AI.Softmax
type Sequential = AI.Sequential

struct GPTConfig {
    int vocab_size
    int embed_dim
    int num_heads
    int ffn_dim
    int num_layers
    int max_seq_len
    float dropout_prob
}

struct GPTModel {
    GPTConfig config
    embedding tok_embed
    embedding pos_embed
    TransformerBlock[] blocks
    LayerNorm final_ln
    Linear output_head
    AG.AutoGradTensor[] all_params
}

func nn_unit_name() string {
    "std/nn"
}

func nn_unit_ready() int {
    1
}

func make_linear(int in_f, int out_f, bool use_bias) Linear {
    AI.new_linear(in_f, out_f, use_bias)
}

func make_embedding(int num_emb, int emb_dim, int pad_idx) embedding {
    AI.new_embedding(num_emb, emb_dim, pad_idx)
}

func make_layer_norm(int[] norm_shape, float eps_val) LayerNorm {
    AI.new_layer_norm(norm_shape, eps_val)
}

func make_mha(int d_model, int n_heads, float drop_p, bool causal) MultiHeadAttention {
    AI.new_mha(d_model, n_heads, drop_p, causal)
}

func make_feed_forward(int d_model, int d_ff, float drop_p, string act_fn) FeedForward {
    AI.new_feed_forward(d_model, d_ff, drop_p, act_fn)
}

func make_transformer_block(int d_model, int n_heads, int d_ff, float drop_p, bool pre_norm) TransformerBlock {
    AI.new_transformer_block(d_model, n_heads, d_ff, drop_p, pre_norm)
}

func make_dropout(float prob) Dropout {
    AI.new_dropout(prob)
}

func make_relu_mod() ReLU_Mod {
    AI.new_relu()
}

func make_gelu_mod() GELU_Mod {
    AI.new_gelu()
}

func make_sigmoid_mod() Sigmoid_Mod {
    AI.new_sigmoid()
}

func make_softmax_mod(int d) Softmax_Mod {
    AI.new_softmax(d)
}

func make_sequential() Sequential {
    AI.new_sequential(new AI.Module[0])
}

func set_train(Module mut m, bool mode) void {
    AI.train_mode(m, mode)
}

func get_params(Module m) AG.AutoGradTensor[] {
    AI.get_parameters(m)
}

func count_params(Module m) int {
    AI.count_parameters(m)
}

func module_summary(Module m, string indent) void {
    AI.print_module_summary(m, indent)
}

func default_gpt_config() GPTConfig {
    GPTConfig {
        vocab_size: 256,
        embed_dim: 128,
        num_heads: 4,
        ffn_dim: 512,
        num_layers: 4,
        max_seq_len: 32,
        dropout_prob: 0.1,
    }
}

func make_gpt(GPTConfig cfg) GPTModel {
    GPTModel model
    model.config = cfg
    model.tok_embed = make_embedding(cfg.vocab_size, cfg.embed_dim, -1)
    model.pos_embed = make_embedding(cfg.max_seq_len, cfg.embed_dim, -1)
    model.blocks = new TransformerBlock[cfg.num_layers]

    int i = 0
    while i < cfg.num_layers {
        model.blocks[i] = make_transformer_block(
            cfg.embed_dim,
            cfg.num_heads,
            cfg.ffn_dim,
            cfg.dropout_prob,
            true
        )
        i = i + 1
    }

    model.final_ln = make_layer_norm([cfg.embed_dim], 1e-5)
    model.output_head = make_linear(cfg.embed_dim, cfg.vocab_size, false)
    collect_gpt_params(model)
    model
}

func copy_params_into(AG.AutoGradTensor[] dst, int start_pos, AG.AutoGradTensor[] src) int {
    int i = 0
    while i < len(src) {
        dst[start_pos + i] = src[i]
        i = i + 1
    }
    start_pos + i
}

func collect_gpt_params(GPTModel mut model) void {
    int total = count_params(model.tok_embed) + count_params(model.pos_embed)
    int i = 0
    while i < model.config.num_layers {
        total = total + count_params(model.blocks[i])
        i = i + 1
    }
    total = total + count_params(model.final_ln) + count_params(model.output_head)

    model.all_params = new AG.AutoGradTensor[total]
    int pos = 0
    pos = copy_params_into(model.all_params, pos, get_params(model.tok_embed))
    pos = copy_params_into(model.all_params, pos, get_params(model.pos_embed))

    i = 0
    while i < model.config.num_layers {
        pos = copy_params_into(model.all_params, pos, get_params(model.blocks[i]))
        i = i + 1
    }

    pos = copy_params_into(model.all_params, pos, get_params(model.final_ln))
    pos = copy_params_into(model.all_params, pos, get_params(model.output_head))
}

func gpt_total_params(GPTModel self) int {
    int total = 0
    int i = 0
    while i < len(self.all_params) {
        total = total + AG.num_parameters(self.all_params[i])
        i = i + 1
    }
    total
}

func forward(GPTModel self, int[] token_ids, int batch_size, int seq_len) AG.AutoGradTensor {
    AG.AutoGradTensor tok_emb = AI.forward(self.tok_embed, token_ids, batch_size, seq_len)

    int total_tokens = batch_size * seq_len
    int[] pos_ids = new int[total_tokens]
    int idx = 0
    while idx < total_tokens {
        pos_ids[idx] = idx % seq_len
        idx = idx + 1
    }

    AG.AutoGradTensor pos_emb = AI.forward(self.pos_embed, pos_ids, batch_size, seq_len)
    AG.AutoGradTensor x = AG.autograd_add(tok_emb, pos_emb)

    int i = 0
    while i < self.config.num_layers {
        x = AI.forward(self.blocks[i], x)
        i = i + 1
    }

    AG.AutoGradTensor normed = AI.forward(self.final_ln, x)
    AI.forward(self.output_head, normed)
}

func print_gpt_summary(GPTModel self) void {
    println("")
    println("╔══════════════════════════════════════════╗")
    println("║         GPT Model Architecture           ║")
    println("╠══════════════════════════════════════════╣")
    println("║  Vocab Size:     " + string(self.config.vocab_size) + "                   ║")
    println("║  Embed Dim:      " + string(self.config.embed_dim) + "                    ║")
    println("║  Num Heads:      " + string(self.config.num_heads) + "                     ║")
    println("║  FFN Dim:        " + string(self.config.ffn_dim) + "                    ║")
    println("║  Num Layers:      " + string(self.config.num_layers) + "                   ║")
    println("║  Max Seq Len:     " + string(self.config.max_seq_len) + "                   ║")
    println("║  Dropout:        " + string(self.config.dropout_prob) + "                      ║")
    println("╠══════════════════════════════════════════╣")
    println("║  TOTAL:           " + string(gpt_total_params(self)) + " parameters          ║")
    println("╚══════════════════════════════════════════╝")
    println("")
}
