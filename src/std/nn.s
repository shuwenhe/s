// ============================================
// S Language Neural Network Modules
// 神经网络模块库 - 可组合的层与模型
// ============================================
//
// 提供构建深度学习模型所需的所有组件:
// - 基础层: Linear, Embedding, LayerNorm, Dropout
// - 注意力机制: Multi-Head Self Attention (Causal)
// - Transformer组件: FeedForward, TransformerBlock  
// - 完整模型: GPT (Generative Pre-trained Transformer)
//
// 设计模式:
// - Module基类 + 组合式构建 (类似PyTorch nn.Module)
// - 每个Module包含参数列表和forward函数
// - 支持嵌套: TransformerBlock 包含 MHA + FFN
// ============================================

package std.nn

use std.tensor_core as T
use std.math_dl as M
use std.autograd as AG

// ============================================
// Module Base Class & Utilities (模块基类)
// ============================================

struct Module {
    string type_name        // "Linear", "Embedding", "MHA", etc.
    AG.AGTensor[] params   // 所有可训练参数 (AGTensor形式)
    bool training          // 训练 vs 推理模式 (影响Dropout等)
}

func make_module(string tname) Module {
    Module { type_name: tname, params: new AG.AGTensor[0], training: true }
}

// 获取所有参数
func get_params(Module m) AG.AGTensor[] { m.params }

// 统计总参数量
func count_params(Module m) int {
    int total = 0
    int i = 0
    while i < len(m.params) {
        total = total + AG.num_params(m.params[i])
        i = i + 1
    }
    total
}

// 设置训练/评估模式
func set_train(Module mut m, bool mode) void { m.training = mode }

// 添加一个参数到模块
func add_param(Module mut m, T.Tensor data, string name) void {
    AG.AGTensor p = AG.parameter(data, m.type_name + "." + name)
    // append to params (S语言可能不支持动态数组append，这里用索引方式模拟)
    int n = len(m.params)
    if n == 0 || true {
        m.params = realloc_agtensor_array(m.params, n + 1)
        m.params[n] = p
    }
}

// 打印模块摘要信息
func module_summary(Module m, string indent) void {
    println(indent + m.type_name + ": " + string(count_params(m)) + " parameters")
    
    // 如果有子模块也打印（对于容器类型）
    if m.type_name == "Sequential" {
        Sequential seq = m as Sequential  // 类型转换需要运行时支持
        int i = 0
        while i < seq.count {
            module_summary(seq.layers[i], indent + "  ")
            i = i + 1
        }
    }
}

// 动态调整AGTensor数组大小 ( workaround for S's limited array support)
func realloc_agtensor_array(AG.AGTensor[] arr, int new_size) AG.AGTensor[] {
    AG.AGTensor[] new_arr = new AG.AGTensor[new_size]
    int copy_n = len(arr)
    if copy_n > new_size { copy_n = new_size }
    int i = 0
    while i < copy_n { new_arr[i] = arr[i]; i = i + 1 }
    new_arr
}

// ============================================
// Linear Layer (全连接层): y = xA^T + b
// ============================================

struct Linear : Module {
    AG.AGTensor weight   // shape: (out_features, in_features)
    AG.AGTensor bias     // shape: (out_features,) 或 nil
    int in_feat
    int out_feat
}

// 创建全连接层
// Xavier/Glorot 初始化权重
func make_linear(int in_f, int out_f, bool use_bias) Linear {
    Linear layer
    layer.type_name = "Linear"
    layer.in_feat = in_f
    layer.out_feat = out_f
    
    // 权重初始化: Xavier Uniform
    float limit = sqrt(6.0 / ((in_f as float) + (out_f as float)))
    int[] wshape = [out_f, in_f]
    T.Tensor w_data = T.rand(wshape)
    int i = 0
    while i < w_data.shape.size {
        w_data.data[i] = (w_data.data[i] * 2.0 - 1.0) * limit
        i = i + 1
    }
    layer.weight = AG.parameter(w_data, "weight")
    
    // 偏置初始化为零
    if use_bias {
        int[] bshape = [out_f]
        T.Tensor b_data = T.zeros(bshape)
        layer.bias = AG.parameter(b_data, "bias")
    }
    
    // 收集参数到模块
    layer.params = new AG.AGTensor[1]
    layer.params[0] = layer.weight
    if use_bias {
        layer.params = realloc_agtensor_array(layer.params, 2)
        layer.params[1] = layer.bias
    }
    
    layer
}

// 前向传播: output = input @ weight.T + bias
// 输入 x 形状: (*, in_features)
// 输出形状: (*, out_features)
func forward(Linear self, AG.AGTensor x) AG.AGTensor {
    // 矩阵乘法: x @ W^T
    AG.AGTensor out = AG.ag_matmul(x, self.weight)
    
    // 加偏置 (广播)
    if self.out_feat > 0 && len(self.params) > 1 {
        out = AG.ag_add(out, self.bias)
    }
    
    out
}

// ============================================
// Embedding Layer (词嵌入层)
// 从词表索引查找对应的嵌入向量
// ============================================

struct Embedding : Module {
    AG.AGTensor weight      // (num_embeddings, embedding_dim)
    int num_embed           // 词表大小
    int embed_dim           // 嵌入维度
    int padding_idx         // 特殊padding token的ID (-1表示无)
}

// 创建嵌入层
// 初始化: N(0, 1) 正态分布
func make_embedding(int num_emb, int emb_dim, int pad_idx) Embedding {
    Embedding layer
    layer.type_name = "Embedding"
    layer.num_embed = num_emb
    layer.embed_dim = emb_dim
    layer.padding_idx = pad_idx
    
    int[] wshape = [num_emb, emb_dim]
    T.Tensor w_data = T.randn(wshape, 0.0, 1.0)
    layer.weight = AG.parameter(w_data, "weight")
    
    layer.params = new AG.AGTensor[1]
    layer.params[0] = layer.weight
    
    layer
}

// 前向传播: 查找每个token ID对应的嵌入向量
// 输入: token_ids 一维数组, 长度 batch*seq_len
// 输出: (batch_size, seq_len, embedding_dim)
func forward(Embedding self, int[] token_ids, int batch_size, int seq_len) AG.AGTensor {
    int total_tokens = batch_size * seq_len
    
    // 查找嵌入向量并组装输出
    float[] out_vals = new float[total_tokens * self.embed_dim]
    
    int idx = 0
    while idx < total_tokens {
        int tid = token_ids[idx]
        
        // 处理padding
        if tid == self.padding_idx && self.padding_idx >= 0 {
            // padding位置填零
            int j = 0
            while j < self.embed_dim {
                out_vals[idx * self.embed_dim + j] = 0.0
                j = j + 1
            }
        } else if tid >= 0 && tid < self.num_embed {
            // 查表获取嵌入向量
            int offset = tid * self.embed_dim
            int j = 0
            while j < self.embed_dim {
                out_vals[idx * self.embed_dim + j] = self.weight.data.data[offset + j]
                j = j + 1
            }
        }
        // 越界token默认为0
        
        idx = idx + 1
    }
    
    int[] oshape = [batch_size, seq_len, self.embed_dim]
    T.Tensor out_data = T.make_tensor(out_vals, oshape)
    
    AG.from_tensor(out_data)
}

// ============================================
// Layer Normalization (层归一化)
// 对最后一维归一化: y = γ*(x-μ)/√(σ²+ε) + β
// ============================================

struct LayerNorm : Module {
    AG.AGTensor gamma       // 缩放参数 γ (normalized_shape,)
    AG.AGTensor beta        // 偏移参数 β (normalized_shape,)
    int[] norm_shape        // 要归一化的维度
    float eps               // 数值稳定常数
}

// 创建LayerNorm
func make_layer_norm(int[] norm_shape, float eps_val) LayerNorm {
    LayerNorm layer
    layer.type_name = "LayerNorm"
    layer.norm_shape = norm_shape
    layer.eps = eps_val
    
    // gamma初始化为1
    T.Tensor g_data = T.ones(norm_shape)
    layer.gamma = AG.parameter(g_data, "gamma")
    
    // beta初始化为0
    T.Tensor b_data = T.zeros(norm_shape)
    layer.beta = AG.parameter(b_data, "beta")
    
    layer.params = new AG.AGTensor[2]
    layer.params[0] = layer.gamma
    layer.params[1] = layer.beta
    
    layer
}

// 前向传播
func forward(LayerNorm self, AG.AGTensor x) AG.AGTensor {
    // 使用tensor_core的layer_norm实现
    AG.AGTensor normalized = AG.ag_layer_norm(x, self.eps)
    
    // 缩放和偏移: y = gamma * normalized + beta
    AG.AGTensor scaled = AG.ag_mul(normalized, self.gamma)
    AG.AGTensor output = AG.ag_add(scaled, self.beta)
    
    output
}

// ============================================
// Multi-Head Self Attention (多头自注意力)
// 实现"Scaled Dot-Product Attention" (Vaswani et al., 2017)
// 支持 causal mask 用于自回归模型 (如GPT)
// ============================================

struct MultiHeadAttention : Module {
    Linear q_proj       // Query 投影
    Linear k_proj       // Key 投影
    Linear v_proj       // Value 投影
    Linear out_proj     // 输出投影
    int num_heads       // 注意力头数 H
    int head_dim        // 每头维度 d_k = D/H
    int embed_dim       // 总维度 D
    float dropout_p     // Dropout概率
    bool is_causal      // 是否使用因果掩码 (下三角)
}

// 创建多头注意力层
func make_mha(int d_model, int n_heads, float drop_p, bool causal) MultiHeadAttention {
    MultiHeadAttention attn
    attn.type_name = "MultiHeadAttention"
    attn.embed_dim = d_model
    attn.num_heads = n_heads
    attn.head_dim = d_model / n_heads
    attn.dropout_p = drop_p
    attn.is_causal = causal
    
    // Q/K/V/O 四个线性投影 (均不使用bias以减少参数)
    attn.q_proj = make_linear(d_model, d_model, false)
    attn.k_proj = make_linear(d_model, d_model, false)
    attn.v_proj = make_linear(d_model, d_model, false)
    attn.out_proj = make_linear(d_model, d_model, false)
    
    // 收集所有子模块参数
    int total = count_params(attn.q_proj) + count_params(attn.k_proj) + 
                count_params(attn.v_proj) + count_params(attn.out_proj)
    attn.params = new AG.AGTensor[total]
    int pos = 0
    pos = copy_params_into(attn.params, pos, attn.q_proj.params)
    pos = copy_params_into(attn.params, pos, attn.k_proj.params)
    pos = copy_params_into(attn.params, pos, attn.v_proj.params)
    pos = copy_params_into(attn.params, pos, attn.out_proj.params)
    
    attn
}

// 辅助: 复制参数到数组
func copy_params_into(AG.AGTensor[] dst, int start_pos, AG.AGTensor[] src) int {
    int i = 0
    while i < len(src) {
        dst[start_pos + i] = src[i]
        i = i + 1
    }
    start_pos + i
}

// 前向传播
// x: (batch, seq_len, d_model)
// mask: 可选的注意力掩码 (batch, 1, seq_len, seq_len), nil表示无掩码
func forward(MultiHeadAttention self, AG.AGTensor x, T.Tensor mask) AG.AGTensor {
    int B = x.data.shape.dims[0]    // batch size
    int S = x.data.shape.dims[1]    // sequence length
    int D = self.embed_dim          // model dim
    int H = self.num_heads          // heads
    int dk = self.head_dim          // per-head dim

    // Step 1: QKV投影
    AG.AGTensor Q = forward(self.q_proj, x)  // (B, S, D)
    AG.AGTensor K = forward(self.k_proj, x)
    AG.AGTensor V = forward(self.v_proj, x)

    // Step 2: Reshape to multi-head format
    // (B, S, D) -> (B, S, H, dk) -> (B, H, S, dk)
    int[] reshape_to = [B, S, H, dk]
    Q = AG.ag_view(Q, reshape_to)
    K = AG.ag_view(K, reshape_to)
    V = AG.ag_view(V, reshape_to)
    
    // 转置: (B, S, H, dk) -> (B, H, S, dk)
    Q = AG.ag_transpose(Q, 1, 2)
    K = AG.ag_transpose(K, 1, 2)
    V = AG.ag_transpose(V, 1, 2)

    // Step 3: Scaled dot-product attention
    // scores = Q @ K^T / sqrt(dk)
    AG.AGTensor K_T = AG.ag_transpose(K, 2, 3)  // (B, H, dk, S)
    AG.AGTensor scores = AG.ag_matmul(Q, K_T)     // (B, H, S, S)

    // 缩放
    float scale = sqrt(dk as float)
    AG.AGTensor scaled_scores = AG.ag_div(scores, AG.from_tensor(T.scalar(scale)))

    // 应用因果mask (下三角)
    if self.is_causal {
        T.Tensor causal_mask = _make_causal_mask(S)
        scaled_scores = AG.ag_add(scaled_scores, AG.from_tensor(causal_mask))
    }
    
    // 应用外部提供的mask (如padding mask)
    // if mask != nil { ... }

    // Step 4: Softmax over keys dimension
    AG.AGTensor attn_weights = AG.ag_softmax(scaled_scores, 3)  // dim=3 (keys)

    // Dropout on attention weights (训练时)
    if self.dropout_p > 0 {
        T.Tensor dropped = T.dropout(attn_weights.data, self.dropout_p, true)
        attn_weights = AG.from_tensor(dropped)
    }

    // Step 5: Weighted sum of values
    // context = attn_weights @ V  => (B, H, S, dk)
    AG.AGTensor context = AG.ag_matmul(attn_weights, V)

    // Step 6: Merge heads & project output
    // (B, H, S, dk) -> (B, S, H, dk) -> (B, S, D)
    context = AG.ag_transpose(context, 1, 2)  // -> (B, S, H, dk)
    int[] merge_shape = [B, S, D]
    context = AG.ag_view(context, merge_shape)

    // Output projection
    AG.AGTensor output = forward(self.out_proj, context)
    
    output
}

// 创建下三角因果mask
func _make_causal_mask(int seq_len) T.Tensor {
    int sz = seq_len * seq_len
    float[] vals = new float[sz]
    
    int r = 0
    while r < seq_len {
        int c = 0
        while c < seq_len {
            if c > r { vals[r * seq_len + c] = T.FLOAT_NEG_INF }  // 屏蔽未来位置
            else { vals[r * seq_len + c] = 0.0 }
            c = c + 1
        }
        r = r + 1
    }
    
    int[] shape = [seq_len, seq_len]
    T.make_tensor(vals, shape)
}

// ============================================
// Feed-Forward Network (前馈神经网络)
// 结构: Linear -> Activation -> (Dropout) -> Linear
// 通常用于Transformer中每个注意力块之后
// ============================================

struct FeedForward : Module {
    Linear fc1             // 第一层: d_model -> d_ff
    Linear fc2             // 第二层: d_ff -> d_model
    float dropout_prob
    string activation      // "relu" | "gelu" | "silu"
}

// 创建FFN层
func make_feed_forward(int d_model, int d_ff, float drop_p, string act_fn) FeedForward {
    FeedForward ff
    ff.type_name = "FeedForward"
    ff.dropout_prob = drop_p
    ff.activation = act_fn
    
    ff.fc1 = make_linear(d_model, d_ff, true)
    ff.fc2 = make_linear(d_ff, d_model, true)
    
    int total = count_params(ff.fc1) + count_params(ff.fc2)
    ff.params = new AG.AGTensor[total]
    int pos = 0
    pos = copy_params_into(ff.params, pos, ff.fc1.params)
    pos = copy_params_into(ff.params, pos, ff.fc2.params)
    
    ff
}

// 前向传播
func forward(FeedForward self, AG.AGTensor x) AG.AGTensor {
    // 第一层变换
    AG.AGTensor h = forward(self.fc1, x)
    
    // 激活函数
    if self.activation == "relu" { h = AG.ag_relu(h) }
    else if self.activation == "gelu" { h = AG.ag_gelu(h) }
    else if self.activation == "silu" { h = ag_silu(h) }  // x * sigmoid(x)
    
    // Dropout (仅训练时)
    if self.dropout_prob > 0 {
        T.Tensor dropped = T.dropout(h.data, self.dropout_prob, true)
        h = AG.from_tensor(dropped)
    }
    
    // 第二层变换
    AG.AGTensor output = forward(self.fc2, h)
    
    output
}

// SiLU/Swish激活: x * sigmoid(x)
func ag_silu(AG.AGTensor x) AG.AGTensor {
    AG.AGTensor sig = AG.ag_sigmoid(x)
    AG.ag_mul(x, sig)
}

// ============================================
// Transformer Block (Transformer 编码器块)
// 采用 Pre-LayerNorm 架构 (GPT-2风格):
//   x = x + Attention(LayerNorm(x))
//   x = x + FFN(LayerNorm(x))
// ============================================

struct TransformerBlock : Module {
    MultiHeadAttention attn
    FeedForward ff_net
    LayerNorm norm1          // 第一个LayerNorm (Attention前)
    LayerNorm norm2          // 第二个LayerNorm (FFN前)
    float dropout_prob
    bool use_pre_norm        // true=Pre-LN(GPT-2), false=Post-LN(原版Transformer)
}

// 创建Transformer Block
func make_transformer_block(int d_model, int n_heads, int d_ff, 
                              float drop_p, bool pre_norm) TransformerBlock {
    TransformerBlock block
    block.type_name = "TransformerBlock"
    block.attn = make_mha(d_model, n_heads, drop_p, true)  // 默认causal
    block.ff_net = make_feed_forward(d_model, d_ff, drop_p, "gelu")
    block.norm1 = make_layer_norm([d_model], 1e-5)
    block.norm2 = make_layer_norm([d_model], 1e-5)
    block.dropout_prob = drop_p
    block.use_pre_norm = pre_norm
    
    // 收集所有子模块参数
    int np_attn = count_params(block.attn)
    int np_ff = count_params(block.ff_net)
    int np_n1 = count_params(block.norm1)
    int np_n2 = count_params(block.norm2)
    int total = np_attn + np_ff + np_n1 + np_n2
    block.params = new AG.AGTensor[total]
    int pos = 0
    pos = copy_params_into(block.params, pos, block.attn.params)
    pos = copy_params_into(block.params, pos, block.ff_net.params)
    pos = copy_params_into(block.params, pos, block.norm1.params)
    pos = copy_params_into(block.params, pos, block.norm2.params)
    
    block
}

// 前向传播 (Pre-Norm版本)
func forward(TransformerBlock self, AG.AGTensor x) AG.AGTensor {
    if self.use_pre_norm {
        // ===== Pre-LN (GPT-2 style) =====
        
        // Sub-layer 1: Self-Attention with residual
        AG.AGTensor normed1 = forward(self.norm1, x)
        AG.AGTensor attn_out = forward(self.attn, normed1, T.tensor(new float[0], new int[0]))  // 无额外mask
        
        // Residual connection + optional dropout
        AG.AGTensor h = AG.ag_add(x, attn_out)
        if self.dropout_prob > 0 {
            T.Tensor dropped = T.dropout(h.data, self.dropout_prob, true)
            h = AG.from_tensor(dropped)
        }
        
        // Sub-layer 2: Feed-Forward with residual
        AG.AGTensor normed2 = forward(self.norm2, h)
        AG.AGTensor ff_out = forward(self.ff_net, normed2)
        
        // Residual connection
        AG.AGTensor output = AG.ag_add(h, ff_out)
        if self.dropout_prob > 0 {
            T.Tensor dropped2 = T.dropout(output.data, self.dropout_prob, true)
            output = AG.from_tensor(dropped2)
        }
        
        return output
    } else {
        // ===== Post-LN (Original Transformer style) =====
        
        AG.AGTensor attn_out = forward(self.attn, x, T.tensor(new float[0], new int[0]))
        AG.AGTensor h = AG.ag_add(x, attn_out)
        h = forward(self.norm1, h)
        
        AG.AGTensor ff_out = forward(self.ff_net, h)
        AG.AGTensor output = AG.ag_add(h, ff_out)
        output = forward(self.norm2, output)
        
        return output
    }
}

// ============================================
// Dropout Layer (丢弃层)
// ============================================

struct Dropout : Module {
    float probability
}

func make_dropout(float prob) Dropout {
    Dropout { type_name: "Dropout", probability: prob, params: new AG.AGTensor[0], training: true }
}

func forward(Dropout self, AG.AGTensor x) AG.AGTensor {
    if !self.training || self.probability <= 0.0 { return x }
    T.Tensor dropped = T.dropout(x.data, self.probability, true)
    AG.from_tensor(dropped)
}

// ============================================
// Activation Modules (激活函数作为模块)
// ============================================

struct ReLU_Mod : Module {}
func make_relu_mod() ReLU_Mod { ReLU_Mod { type_name: "ReLU", params: new AG.AGTensor[0], training: true } }
func forward(ReLU_Mod self, AG.AGTensor x) AG.AGTensor { AG.ag_relu(x) }

struct GELU_Mod : Module {}
func make_gelu_mod() GELU_Mod { GELU_Mod { type_name: "GELU", params: new AG.AGTensor[0], training: true } }
func forward(GELU_Mod self, AG.AGTensor x) AG.AGTensor { AG.ag_gelu(x) }

struct Sigmoid_Mod : Module {}
func make_sigmoid_mod() Sigmoid_Mod { Sigmoid_Mod { type_name: "Sigmoid", params: new AG.AGTensor[0], training: true } }
func forward(Sigmoid_Mod self, AG.AGTensor x) AG.AGTensor { AG.ag_sigmoid(x) }

struct Softmax_Mod : Module {
    int dim
}
func make_softmax_mod(int d) Softmax_Mod { Softmax_Mod { type_name: "Softmax", dim: d, params: new AG.AGTensor[0], training: true } }
func forward(Softmax_Mod self, AG.AGTensor x) AG.AGTensor { AG.ag_softmax(x, self.dim) }

// ============================================
// Sequential Container (顺序容器)
// 按顺序执行多个子模块
// ============================================

struct Sequential : Module {
    Module[] layers
    int count
}

func make_sequential() Sequential {
    Sequential { type_name: "Sequential", layers: new Module[16], count: 0, params: new AG.AGTensor[0], training: true }
}

func seq_add(Sequential mut self, Module layer) void {
    if self.count < 16 {
        self.layers[self.count] = layer
        self.count = self.count + 1
    }
}

func forward(Sequential self, AG.AGTensor x) AG.AGTensor {
    AG.AGTensor output = x
    int i = 0
    while i < self.count {
        output = forward(self.layers[i], output)
        i = i + 1
    }
    output
}

// ============================================
// Complete GPT Model (完整GPT模型)
// Generative Pre-trained Transformer for language modeling
// ============================================

struct GPTConfig {
    int vocab_size          // 词表大小 V
    int embed_dim           // 嵌入/隐藏维度 D
    int num_heads           // 注意力头数 H
    int ffn_dim             // FFN中间维度 (通常4D)
    int num_layers          // Transformer层数 L
    int max_seq_len         // 最大序列长度
    float dropout_prob      // Dropout率
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

struct GPTModel {
    GPTConfig config
    Embedding tok_embed     // Token Embedding: (V, D)
    Embedding pos_embed     // Position Embedding: (S_max, D)
    TransformerBlock[] blocks  // L个Transformer块
    LayerNorm final_ln      // 最终LayerNorm
    Linear output_head      // 输出投影: (D, V)
    
    AG.AGTensor[] all_params  // 所有可训练参数
}

// 创建GPT模型
func make_gpt(GPTConfig cfg) GPTModel {
    GPTModel model
    model.config = cfg
    
    // Token嵌入: (vocab_size, embed_dim)
    model.tok_embed = make_embedding(cfg.vocab_size, cfg.embed_dim, -1)
    
    // 位置嵌入: (max_seq_len, embed_dim)
    model.pos_embed = make_embedding(cfg.max_seq_len, cfg.embed_dim, -1)
    
    // Transformer块堆叠
    model.blocks = new TransformerBlock[cfg.num_layers]
    int i = 0
    while i < cfg.num_layers {
        model.blocks[i] = make_transformer_block(
            cfg.embed_dim, cfg.num_heads, cfg.ffn_dim,
            cfg.dropout_prob, true  // Pre-LN
        )
        i = i + 1
    }
    
    // 最终层归一化
    model.final_ln = make_layer_norm([cfg.embed_dim], 1e-5)
    
    // 输出头 (投影回词表空间)
    model.output_head = make_linear(cfg.embed_dim, cfg.vocab_size, false)
    
    // 收集所有参数
    collect_gpt_params(model)
    
    model
}

// 收集GPT模型的所有参数到一个数组
func collect_gpt_params(GPTModel mut model) void {
    // 计算总参数数
    int total = count_params(model.tok_embed) + count_params(model.pos_embed)
    int i = 0
    while i < model.config.num_layers {
        total = total + count_params(model.blocks[i])
        i = i + 1
    }
    total = total + count_params(model.final_ln) + count_params(model.output_head)
    
    model.all_params = new AG.AGTensor[total]
    int pos = 0
    pos = copy_params_into(model.all_params, pos, model.tok_embed.params)
    pos = copy_params_into(model.all_params, pos, model.pos_embed.params)
    
    i = 0
    while i < model.config.num_layers {
        pos = copy_params_into(model.all_params, pos, model.blocks[i].params)
        i = i + 1
    }
    
    pos = copy_params_into(model.all_params, pos, model.final_ln.params)
    pos = copy_params_into(model.all_params, pos, model.output_head.params)
}

// 统计GPT模型的总参数量
func gpt_total_params(GPTModel self) int {
    int total = 0
    int i = 0
    while i < len(self.all_params) {
        total = total + AG.num_params(self.all_params[i])
        i = i + 1
    }
    total
}

// GPT前向传播
// token_ids: (batch_size * seq_len) 扁平化的token ID数组
// 返回: logits (batch_size, seq_len, vocab_size)
func forward(GPTModel self, int[] token_ids, int batch_size, int seq_len) AG.AGTensor {
    int D = self.config.embed_dim
    
    // Step 1: Token embeddings lookup
    AG.AGTensor tok_emb = forward(self.tok_embed, token_ids, batch_size, seq_len)
    
    // Step 2: Position embeddings
    int total_tokens = batch_size * seq_len
    int[] pos_ids = new int[total_tokens]
    int idx = 0
    while idx < total_tokens {
        pos_ids[idx] = idx % seq_len  // 循环位置编码
        idx = idx + 1
    }
    AG.AGTensor pos_emb = forward(self.pos_embed, pos_ids, batch_size, seq_len)
    
    // Step 3: Combine embeddings
    AG.AGTensor x = AG.ag_add(tok_emb, pos_emb)
    
    // Step 4: Pass through transformer blocks
    int i = 0
    while i < self.config.num_layers {
        x = forward(self.blocks[i], x)
        i = i + 1
    }
    
    // Step 5: Final layer norm
    AG.AGTensor normed = forward(self.final_ln, x)
    
    // Step 6: Project to vocabulary
    AG.AGTensor logits = forward(self.output_head, normed)
    
    logits
}

// 打印GPT模型架构摘要
func print_gpt_summary(GPTModel self) void {
    GPTConfig cfg = self.config
    println("")
    println("╔══════════════════════════════════════════╗")
    println("║         GPT Model Architecture           ║")
    println("╠══════════════════════════════════════════╣")
    println("║  Vocab Size:     ", string(cfg.vocab_size), "                   ║")
    println("║  Embed Dim:      ", string(cfg.embed_dim), "                    ║")
    println("║  Num Heads:      ", string(cfg.num_heads), "                     ║")
    println("║  FFN Dim:        ", string(cfg.ffn_dim), "                    ║")
    println("║  Num Layers:      ", string(cfg.num_layers), "                    ║")
    println("║  Max Seq Len:     ", string(cfg.max_seq_len), "                   ║")
    println("║  Dropout:        ", M.fmt_float(cfg.dropout_prob, 2), "                      ║")
    println("╠══════════════════════════════════════════╣")
    
    int tp = count_params(self.tok_embed)
    int pp = count_params(self.pos_embed)
    int bp = 0
    int i = 0
    while i < cfg.num_layers { bp = bp + count_params(self.blocks[i]); i = i + 1 }
    int np = count_params(self.final_ln)
    int op = count_params(self.output_head)
    int total = gpt_total_params(self)
    
    println("║  Token Embed:     ", format_int(tp), " params              ║")
    println("║  Pos Embed:       ", format_int(pp), " params              ║")
    println("║  Transformer:    ", format_int(bp), " params (x", string(cfg.num_layers), ")         ║")
    println("║  Final LayerNorm:", format_int(np), " params              ║")
    println("║  Output Head:     ", format_int(op), " params              ║")
    println("╠══════════════════════════════════════════╣")
    println("║  TOTAL:           ", format_int(total), " parameters          ║")
    println("╚══════════════════════════════════════════╝")
    println("")
}

// 格式化整数 (带千分位分隔符)
func format_int(int n) string {
    string s = ""
    if n == 0 { s = "0" }
    else {
        bool neg = n < 0
        if neg { n = -n }
        string digits = ""
        int group = 0
        while n > 0 {
            if group > 0 && group % 3 == 0 { digits = "," + digits }
            digits = string((n % 10) + 48) + digits
            n = n / 10
            group = group + 1
        }
        if neg { s = "-" + digits }
        else { s = digits }
    }
    s
}
