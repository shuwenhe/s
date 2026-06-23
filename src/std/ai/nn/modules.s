// ============================================
// S Language Neural Network Module Library
// 神经网络模块库 - 可组合的层
// ============================================
package std.ai.nn

use std.tensor.{Tensor, zeros, ones, randn, xavier_uniform, kaiming_normal, 
                  add, sub, mul, div, matmul_2d, reshape, transpose,
                  relu_tensor, softmax_tensor, layer_norm, sigmoid_tensor, 
                  tanh_tensor, gelu_tensor, dropout as tensor_dropout}
use std.math.{sqrt, exp, tanh}
use std.ai.autograd.{AutoGradTensor, parameter, create_autograd_tensor}

// ============================================
// Module Base Class (模块基类)
// ============================================

struct Module {
    string name
    string type_name  // "Linear", "Embedding", "TransformerBlock", etc.
    AutoGradTensor[] parameters  // Learnable parameters
    Map<string, Tensor> buffers  // Non-learnable state (running stats, etc.)
    
    func forward(AutoGradTensor input) AutoGradTensor  // To be implemented by subclasses
}

func module_init(string name, string type_name) Module {
    Module {
        name: name,
        type_name: type_name,
        parameters: new AutoGradTensor[0],
        buffers: new_map(),
    }
}

func add_param(Module mut m, Tensor data, string param_name) void {
    AutoGradTensor p = parameter(data, m.name + "." + param_name)
    append(m.parameters, p)
}

// Get all parameters from a module
func get_parameters(Module m) AutoGradTensor[] { m.parameters }

// Count total parameters
func count_parameters(Module m) int {
    int total = 0
    int i = 0
    while i < len(m.parameters) {
        total = total + num_parameters(m.parameters[i])
        i = i + 1
    }
    total
}

// Set training mode for a module
func train_mode(Module mut m, bool mode) void {
    m.training = mode
    // Recursively set for child modules if any
}

// ============================================
// Linear Layer (全连接层): y = xA^T + b
// ============================================

struct Linear : Module {
    AutoGradTensor weight  // (out_features, in_features)
    AutoGradTensor bias    // (out_features,)
    int in_features
    int out_features
    bool bias_enabled
}

func new_linear(int in_feat, int out_feat, bool use_bias) Linear {
    Linear layer
    layer.type_name = "Linear"
    layer.in_features = in_feat
    layer.out_features = out_feat
    layer.bias_enabled = use_bias
    
    // Xavier uniform initialization
    int[] fan_in = [in_feat]
    int[] fan_out = [out_feat]
    Tensor w_data = xavier_uniform(fan_in, fan_out)
    layer.weight = parameter(w_data, "weight")
    
    if use_bias {
        Tensor b_data = zeros([out_feat])
        layer.bias = parameter(b_data, "bias")
        append(layer.parameters, layer.bias)
    }
    
    append(layer.parameters, layer.weight)
    layer
}

// Forward: output = input @ weight.T + bias
func forward(Linear self, AutoGradTensor x) AutoGradTensor {
    // x: (*, in_features) -> (*, out_features)
    AutoGradTensor out = autograd_matmul(x, self.weight)
    
    if self.bias_enabled {
        out = autograd_add(out, self.bias)  // Broadcasting bias
    }
    
    out
}

// ============================================
// Embedding Layer (词嵌入层)
// ============================================

struct Embedding : Module {
    AutoGradTensor weight  // (num_embeddings, embedding_dim)
    int num_embeddings
    int embedding_dim
    int padding_idx
}

func new_embedding(int num_embed, int embed_dim, int pad_idx) Embedding {
    Embedding layer
    layer.type_name = "Embedding"
    layer.num_embeddings = num_embed
    layer.embedding_dim = embed_dim
    layer.padding_idx = pad_idx
    
    // Normal initialization: N(0, 1)
    int[] shape = [num_embed, embed_dim]
    Tensor w_data = randn(shape, 0.0, 1.0)
    layer.weight = parameter(w_data, "weight")
    
    append(layer.parameters, layer.weight)
    layer
}

// Forward: lookup embeddings by token indices
// Input: token_ids of shape (batch_size, seq_len)
// Output: (batch_size, seq_len, embedding_dim)
func forward(Embedding self, int[] token_ids, int batch_size, int seq_len) AutoGradTensor {
    int num_tokens = batch_size * seq_len
    
    // Gather embeddings for each token
    float[] emb_values = new float[num_tokens * self.embedding_dim]
    
    int i = 0
    while i < num_tokens {
        int token_id = token_ids[i]
        
        // Handle padding index
        if token_id == self.padding_idx {
            int j = 0
            while j < self.embedding_dim {
                emb_values[i * self.embedding_dim + j] = 0.0
                j = j + 1
            }
        } else if token_id >= 0 && token_id < self.num_embeddings {
            int offset = token_id * self.embedding_dim
            int j = 0
            while j < self.embedding_dim {
                emb_values[i * self.embedding_dim + j] = self.weight.data.values[offset + j]
                j = j + 1
            }
        }
        
        i = i + 1
    }
    
    int[] out_shape = [batch_size, seq_len, self.embedding_dim]
    Tensor out_data = tensor(emb_values, out_shape)
    create_autograd_tensor(out_data, true)
}

// ============================================
// Layer Normalization (层归一化)
// ============================================

struct LayerNorm : Module {
    AutoGradTensor gamma   // Scale parameter (normalized_shape,)
    AutoGradTensor beta    // Shift parameter (normalized_shape,)
    int[] normalized_shape
    float eps
}

func new_layer_norm(int[] norm_shape, float eps) LayerNorm {
    LayerNorm layer
    layer.type_name = "LayerNorm"
    layer.normalized_shape = norm_shape
    layer.eps = eps
    
    // gamma initialized to 1, beta to 0
    int size = 1
    int i = 0
    while i < len(norm_shape) {
        size = size * norm_shape[i]
        i = i + 1
    }
    
    layer.gamma = parameter(ones(norm_shape), "gamma")
    layer.beta = parameter(zeros(norm_shape), "beta")
    
    append(layer.parameters, layer.gamma)
    append(layer.parameters, layer.beta)
    layer
}

// Forward: normalize then scale and shift
func forward(LayerNorm self, AutoGradTensor x) AutoGradTensor {
    // Compute mean and variance along last dimensions
    Tensor mean_val = mean(x.data, -1, true)
    Tensor centered = sub(x.data, mean_val)
    Tensor var_val = mean(square(centered.data), -1, true)
    Tensor std = sqrt(add_scalar(var_val, self.eps))
    Tensor normalized = div(centered.data, std)
    
    // Scale and shift
    Tensor out_data = mul(normalized, self.gamma.data)
    out_data = add(out_data, self.beta.data)
    
    create_autograd_tensor(out_data, x.requires_grad)
}

// ============================================
// Multi-Head Self Attention (多头自注意力)
// ============================================

struct MultiHeadAttention : Module {
    Linear q_proj      // Query projection
    Linear k_proj      // Key projection  
    Linear v_proj      // Value projection
    Linear out_proj    // Output projection
    int num_heads
    int head_dim
    int embed_dim
    float dropout_prob
    bool causal
}

func new_mha(int embed_dim, int num_heads, float dropout_p, bool is_causal) MultiHeadAttention {
    MultiHeadAttention attn
    attn.type_name = "MultiHeadAttention"
    attn.embed_dim = embed_dim
    attn.num_heads = num_heads
    attn.head_dim = embed_dim / num_heads
    attn.dropout_prob = dropout_p
    attn.causal = is_causal
    
    attn.q_proj = new_linear(embed_dim, embed_dim, false)
    attn.k_proj = new_linear(embed_dim, embed_dim, false)
    attn.v_proj = new_linear(embed_dim, embed_dim, false)
    attn.out_proj = new_linear(embed_dim, embed_dim, false)
    
    // Collect all parameters
    int i = 0
    while i < 4 {
        Linear proj = [attn.q_proj, attn.k_proj, attn.v_proj, attn.out_proj][i]
        int j = 0
        while j < len(proj.parameters) {
            append(attn.parameters, proj.parameters[j])
            j = j + 1
        }
        i = i + 1
    }
    
    attn
}

// Forward pass for multi-head attention
// x: (batch_size, seq_len, embed_dim)
// mask: optional attention mask (batch_size, 1, seq_len, seq_len) or None
func forward(MultiHeadAttention self, AutoGradTensor x, Tensor mask) AutoGradTensor {
    int batch_size = x.data.shape.dims[0]
    int seq_len = x.data.shape.dims[1]
    int d_model = self.embed_dim
    int n_heads = self.num_heads
    int d_k = self.head_dim
    
    // Project Q, K, V
    AutoGradTensor Q = forward(self.q_proj, x)  // (B, S, D)
    AutoGradTensor K = forward(self.k_proj, x)
    AutoGradTensor V = forward(self.v_proj, x)
    
    // Reshape to multi-head format: (B, S, D) -> (B, S, H, Dk) -> (B, H, S, Dk)
    Q = autograd_view(Q, [batch_size, seq_len, n_heads, d_k])
    Q = autograd_transpose(Q, 1, 2)  // -> (B, H, S, Dk)
    
    K = autograd_view(K, [batch_size, seq_len, n_heads, d_k])
    K = autograd_transpose(K, 1, 2)
    
    V = autograd_view(V, [batch_size, seq_len, n_heads, d_k])
    V = autograd_transpose(V, 1, 2)
    
    // Scaled dot-product attention
    // scores = Q @ K^T / sqrt(d_k)
    K_T = autograd_transpose(K, 2, 3)  // (B, H, Dk, S)
    AutoGradTensor scores = autograd_matmul(Q, K_T)  // (B, H, S, S)
    
    // Scale factor
    float scale = sqrt(d_k as float)
    AutoGradTensor scaled_scores = div(scores, scalar(scale))
    
    // Apply causal mask if needed
    if self.causal {
        Tensor causal_mask = make_causal_mask(seq_len)
        scaled_scores = add(scaled_scores, causal_mask)
    }
    
    // Apply provided mask
    if mask != nil {
        scaled_scores = add(scaled_scores, mask)
    }
    
    // Softmax over last dimension (keys)
    AutoGradTensor attn_weights = softmax(scaled_scores, -1)
    
    // Optional dropout on attention weights
    if self.dropout_prob > 0 && self.training {
        attn_weights = tensor_dropout(attn_weights.data, self.dropout_prob, true)
        attn_weights = create_autograd_tensor(attn_weights, true)
    }
    
    // Weighted sum of values: attn_weights @ V
    AutoGradTensor context = autograd_matmul(attn_weights, V)  // (B, H, S, Dk)
    
    // Reshape back: (B, H, S, Dk) -> (B, S, H, Dk) -> (B, S, D)
    context = autograd_transpose(context, 1, 2)  // (B, S, H, Dk)
    context = autograd_view(context, [batch_size, seq_len, d_model])  // (B, S, D)
    
    // Output projection
    AutoGradTensor output = forward(self.out_proj, context)
    
    output
}

// Create lower-triangular causal mask
func make_causal_mask(int seq_len) Tensor {
    float[] vals = new float[seq_len * seq_len]
    int i = 0
    while i < seq_len {
        int j = 0
        while j < seq_len {
            if j > i { vals[i * seq_len + j] = NEG_INF }  // Mask future positions
            else { vals[i * seq_len + j] = 0.0 }
            j = j + 1
        }
        i = i + 1
    }
    Tensor { shape: [seq_len, seq_len], data: vals, device: "cpu", requires_grad: false }
}

// ============================================
// Feed-Forward Network (前馈网络)
// ============================================

struct FeedForward : Module {
    Linear fc1          // First linear: d_model -> d_ff
    Linear fc2          // Second linear: d_ff -> d_model
    LayerNorm norm       // Optional pre/post normalization
    float dropout_prob
    string activation    // "relu" | "gelu" | "silu"
}

func new_feed_forward(int d_model, int d_ff, float dropout_p, string act_fn) FeedForward {
    FeedForward ff
    ff.type_name = "FeedForward"
    ff.dropout_prob = dropout_p
    ff.activation = act_fn
    
    ff.fc1 = new_linear(d_model, d_ff, true)
    ff.fc2 = new_linear(d_ff, d_model, true)
    ff.norm = new_layer_norm([d_model], 1e-5)
    
    // Collect parameters
    int[][] linears = [[ff.fc1], [ff.fc2]]
    int li = 0
    while li < 2 {
        Linear l = [ff.fc1, ff.fc2][li]
        int pi = 0
        while pi < len(l.parameters) {
            append(ff.parameters, l.parameters[pi])
            pi = pi + 1
        }
        li = li + 1
    }
    
    int ni = 0
    while ni < 2 {
        append(ff.parameters, ff.norm.parameters[ni])
        ni = ni + 1
    }
    
    ff
}

// Forward: x -> fc1 -> activation -> dropout -> fc2
func forward(FeedForward self, AutoGradTensor x) AutoGradTensor {
    // First linear transformation
    AutoGradTensor h = forward(self.fc1, x)
    
    // Activation function
    if self.activation == "relu" {
        h = autograd_relu(h)
    }
    else if self.activation == "gelu" {
        h = autograd_gelu(h)
    }
    else if self.activation == "silu" {
        h = autograd_silu(h)
    }
    
    // Dropout (if training)
    if self.dropout_prob > 0 && self.training {
        h = tensor_dropout(h.data, self.dropout_prob, true)
        h = create_autograd_tensor(h, true)
    }
    
    // Second linear transformation
    AutoGradTensor output = forward(self.fc2, h)
    
    output
}

// ============================================
// Transformer Block (Transformer 编码器块)
// ============================================

struct TransformerBlock : Module {
    MultiHeadAttention attn
    FeedForward ff_net
    LayerNorm norm1     // Pre-LN or Post-LN first norm
    LayerNorm norm2     // Second norm
    float dropout_prob
    bool pre_norm       // Use pre-norm (GPT-2 style) vs post-norm
}

func new_transformer_block(int d_model, int n_heads, int d_ff, float dropout_p, bool pre_norm) TransformerBlock {
    TransformerBlock block
    block.type_name = "TransformerBlock"
    block.dropout_prob = dropout_p
    block.pre_norm = pre_norm
    
    block.attn = new_mha(d_model, n_heads, dropout_p, true)  // Causal attention
    block.ff_net = new_feed_forward(d_model, d_ff, dropout_p, "gelu")
    block.norm1 = new_layer_norm([d_model], 1e-5)
    block.norm2 = new_layer_norm([d_model], 1e-5)
    
    // Collect all parameters from sub-modules
    // ... (append from attn, ff_net, norm1, norm2)
    
    block
}

// Forward with residual connections
func forward(TransformerBlock self, AutoGradTensor x) AutoGradTensor {
    if self.pre_norm {
        // GPT-2 style: Pre-LayerNorm
        AutoGradTensor normed = forward(self.norm1, x)
        AutoGradTensor attn_out = forward(self.attn, normed, nil)
        
        // Residual connection + dropout
        AutoGradTensor h = add(x, attn_out)
        if self.dropout_prob > 0 {
            h = tensor_dropout(h.data, self.dropout_prob, true)
            h = create_autograd_tensor(h, true)
        }
        
        // FFN with pre-norm
        normed = forward(self.norm2, h)
        AutoGradTensor ff_out = forward(self.ff_net, normed)
        
        // Residual connection
        AutoGradTensor output = add(h, ff_out)
        if self.dropout_prob > 0 {
            output = tensor_dropout(output.data, self.dropout_prob, true)
            output = create_autograd_tensor(output, true)
        }
        
        output
    } else {
        // Original Transformer style: Post-LayerNorm
        AutoGradTensor attn_out = forward(self.attn, x, nil)
        AutoGradTensor h = add(x, attn_out)
        h = forward(self.norm1, h)
        
        AutoGradTensor ff_out = forward(self.ff_net, h)
        AutoGradTensor output = add(h, ff_out)
        output = forward(self.norm2, output)
        
        output
    }
}

// ============================================
// Dropout (丢弃层)
// ============================================

struct Dropout : Module {
    float probability
}

func new_dropout(float prob) Dropout {
    Dropout { probability: prob }
}

func forward(Dropout self, AutoGradTensor x) AutoGradTensor {
    if !self.training || self.probability == 0.0 { return x }
    
    AutoGradTensor result = create_autograd_tensor(
        tensor_dropout(x.data, self.probability, true),
        x.requires_grad
    )
    result
}

// ============================================
// Activation Functions as Modules (激活函数层)
// ============================================

struct ReLU : Module {}
func new_relu() ReLU { ReLU {} }
func forward(ReLU self, AutoGradTensor x) AutoGradTensor { autograd_relu(x) }

struct GELU : Module {}
func new_gelu() GELU { GELU {} }
func forward(GELU self, AutoGradTensor x) AutoGradTensor { autograd_gelu(x) }

struct SiLU : Module {}
func new_silu() SiLU { SiLU {} }
func forward(SiLU self, AutoGradTensor x) AutoGradTensor { autograd_silu(x) }

struct Sigmoid : Module {}
func new_sigmoid() Sigmoid { Sigmoid {} }
func forward(Sigmoid self, AutoGradTensor x) AutoGradTensor { autograd_sigmoid(x) }

struct TanhModule : Module {}
func new_tanh_mod() TanhModule { TanhModule {} }
func forward(TanhModule self, AutoGradTensor x) AutoGradTensor { autograd_tanh(x) }

// Softmax (not learnable, but useful as module)
struct Softmax : Module {
    int dim
}
func new_softmax(int d) Softmax { Softmax { dim: d } }
func forward(Softmax self, AutoGradTensor x) AutoGradTensor { autograd_softmax(x, self.dim) }

// ============================================
// Sequential Container (顺序容器)
// ============================================

struct Sequential : Module {
    Module[] layers
}

func new_sequential(Module[] layers) Sequential {
    Sequential { layers: layers }
}

// Forward through all layers in order
func forward(Sequential self, AutoGradTensor x) AutoGradTensor {
    AutoGradTensor output = x
    int i = 0
    while i < len(self.layers) {
        output = forward(self.layers[i], output)
        i = i + 1
    }
    output
}

// Add a layer to sequential
func add_layer(Sequential mut self, Module layer) void {
    append(self.layers, layer)
}

// ============================================
// Utility Functions (工具函数)
// ============================================

// Initialize weights using specific scheme
func init_weights(Module mut m, string scheme) void {
    int i = 0
    while i < len(m.parameters) {
        if scheme == "xavier_uniform" {
            m.parameters[i].data = xavier_uniform(m.parameters[i].data.shape.dims[:2], m.parameters[i].data.shape.dims[2:])
        }
        else if scheme == "kaiming_normal" {
            m.parameters[i].data = kaiming_normal(m.parameters[i].data.shape)
        }
        else if scheme == "normal" {
            m.parameters[i].data = randn(m.parameters[i].data.shape, 0.0, 0.02)
        }
        i = i + 1
    }
}

// Print module architecture summary
func print_module_summary(Module m, string indent) void {
    println(indent, m.type_name, "(", m.name, ")")
    println(indent, "  Parameters: ", count_parameters(m))
    
    // Recursively print children (for containers)
    if m.type_name == "Sequential" {
        Sequential seq = m as Sequential
        int i = 0
        while i < len(seq.layers) {
            print_module_summary(seq.layers[i], indent + "  ")
            i = i + 1
        }
    }
}

// Count trainable parameters
def count_trainable_params(Module m) int {
    int total = 0
    int i = 0
    while i < len(m.parameters):
        if m.parameters[i].requires_grad:
            total = total + m.parameters[i].data.shape.size
        i = i + 1
    return total

// Move module to device (placeholder for future GPU support)
def to_device(Module mut m, string device) void:
    # Currently only CPU supported
    pass
