package std.nn
use std.ai.nn as ai
use std.ai.autograd as ag
type module = ai.module
type linear = ai.linear
type embedding = ai.embedding
type layer_norm = ai.layer_norm
type multi_head_attention = ai.multi_head_attention
type feed_forward = ai.feed_forward
type transformer_block = ai.transformer_block
type dropout = ai.dropout
type re_lu_mod = ai.re_lu
type gelu_mod = ai.gelu
type sigmoid_mod = ai.sigmoid
type softmax_mod = ai.softmax
type sequential = ai.sequential
struct gpt_config {
    int vocab_size
    int embed_dim
    int num_heads
    int ffn_dim
    int num_layers
    int max_seq_len
    float dropout_prob
}

struct gpt_model {
    gpt_config config
    embedding tok_embed
    embedding pos_embed
    transformer_block[] blocks
    layer_norm final_ln
    linear output_head
    ag.auto_grad_tensor[] all_params
}

func nn_unit_name() string {
    "std/nn"
}

func nn_unit_ready() int {
    1
}

func make_linear(int in_f, int out_f, bool use_bias) linear {
    ai.new_linear(in_f, out_f, use_bias)
}

func make_embedding(int num_emb, int emb_dim, int pad_idx) embedding {
    ai.new_embedding(num_emb, emb_dim, pad_idx)
}

func make_layer_norm([]int norm_shape, float eps_val) layer_norm {
    ai.new_layer_norm(norm_shape, eps_val)
}

func make_mha(int d_model, int n_heads, float drop_p, bool causal) multi_head_attention {
    ai.new_mha(d_model, n_heads, drop_p, causal)
}

func make_feed_forward(int d_model, int d_ff, float drop_p, string act_fn) feed_forward {
    ai.new_feed_forward(d_model, d_ff, drop_p, act_fn)
}

func make_transformer_block(int d_model, int n_heads, int d_ff, float drop_p, bool pre_norm) transformer_block {
    ai.new_transformer_block(d_model, n_heads, d_ff, drop_p, pre_norm)
}

func make_dropout(float prob) dropout {
    ai.new_dropout(prob)
}

func make_relu_mod() re_lu_mod {
    ai.new_relu()
}

func make_gelu_mod() gelu_mod {
    ai.new_gelu()
}

func make_sigmoid_mod() sigmoid_mod {
    ai.new_sigmoid()
}

func make_softmax_mod(int d) softmax_mod {
    ai.new_softmax(d)
}

func make_sequential() sequential {
    ai.new_sequential(new ai.module[0])
}

func set_train(module m, bool mode) void {
    ai.train_mode(m, mode)
}

func get_params(module m) ag.auto_grad_tensor[] {
    ai.get_parameters(m)
}

func count_params(module m) int {
    ai.count_parameters(m)
}

func module_summary(module m, string indent) void {
    ai.print_module_summary(m, indent)
}

func default_gpt_config() gpt_config {
    gpt_config {
        vocab_size: 256, embed_dim 128, num_heads 4, ffn_dim 512, num_layers 4, max_seq_len 32, dropout_prob 0.1,
    }
}

func make_gpt(gpt_config cfg) gpt_model {
    gpt_model model
    model.config = cfg
    model.tok_embed = make_embedding(cfg.vocab_size, cfg.embed_dim, -1)
    model.pos_embed = make_embedding(cfg.max_seq_len, cfg.embed_dim, -1)
    model.blocks = new transformer_block[cfg.num_layers]
    int i = 0
    for i < cfg.num_layers {
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

func copy_params_into(ag.auto_grad_tensor[] dst, int start_pos, ag.auto_grad_tensor[] src) int {
    int i = 0
    for i < len(src) {
        dst[start_pos + i] = src[i]
        i = i + 1
    }
    start_pos + i
}

func collect_gpt_params(gpt_model model) void {
    int total = count_params(model.tok_embed) + count_params(model.pos_embed)
    int i = 0
    for i < model.config.num_layers {
        total = total + count_params(model.blocks[i])
        i = i + 1
    }
    total = total + count_params(model.final_ln) + count_params(model.output_head)
    model.all_params = new ag.auto_grad_tensor[total]
    int pos = 0
    pos = copy_params_into(model.all_params, pos, get_params(model.tok_embed))
    pos = copy_params_into(model.all_params, pos, get_params(model.pos_embed))
    i = 0
    for i < model.config.num_layers {
        pos = copy_params_into(model.all_params, pos, get_params(model.blocks[i]))
        i = i + 1
    }
    pos = copy_params_into(model.all_params, pos, get_params(model.final_ln))
    pos = copy_params_into(model.all_params, pos, get_params(model.output_head))
}

func gpt_total_params(gpt_model self) int {
    int total = 0
    int i = 0
    for i < len(self.all_params) {
        total = total + ag.num_parameters(self.all_params[i])
        i = i + 1
    }
    total
}

func forward(gpt_model self, []int token_ids, int batch_size, int seq_len) ag.auto_grad_tensor {
    ag.auto_grad_tensor tok_emb = ai.forward(self.tok_embed, token_ids, batch_size, seq_len)
    int total_tokens = batch_size * seq_len
    []int pos_ids = new int[total_tokens]
    int idx = 0
    for idx < total_tokens {
        pos_ids[idx] = idx % seq_len
        idx = idx + 1
    }
    ag.auto_grad_tensor pos_emb = ai.forward(self.pos_embed, pos_ids, batch_size, seq_len)
    ag.auto_grad_tensor x = ag.autograd_add(tok_emb, pos_emb)
    int i = 0
    for i < self.config.num_layers {
        x = ai.forward(self.blocks[i], x)
        i = i + 1
    }
    ag.auto_grad_tensor normed = ai.forward(self.final_ln, x)
    ai.forward(self.output_head, normed)
}

func print_gpt_summary(gpt_model self) void {
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
