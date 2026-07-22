package std.ai.nn

use std.tensor.{Tensor, zeros, ones, randn, xavier_uniform, kaiming_normal, 
                  add, sub, mul, div, matmul_2d, reshape, transpose,
                  relu_tensor, softmax_tensor, layer_norm, sigmoid_tensor, 
                  tanh_tensor, gelu_tensor, dropout as tensor_dropout}
use std.math.{sqrt, exp, tanh}
use std.ai.autograd.{AutoGradTensor, parameter, create_autograd_tensor}

struct Module {
    string name
    string type_name
    AutoGradTensor[] parameters
    Map<string, Tensor> buffers

    func forward(AutoGradTensor input) AutoGradTensor
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

func get_parameters(Module m) AutoGradTensor[] { m.parameters }

func count_parameters(Module m) int {
    int total = 0
    int i = 0
    while i < len(m.parameters) {
        total = total + num_parameters(m.parameters[i])
        i = i + 1
    }
    total
}

func train_mode(Module mut m, bool mode) void {
    m.training = mode
}

struct Linear : Module {
    AutoGradTensor weight
    AutoGradTensor bias
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

func forward(Linear self, AutoGradTensor x) AutoGradTensor {
    AutoGradTensor out = autograd_matmul(x, self.weight)

    if self.bias_enabled {
        out = autograd_add(out, self.bias)
    }

    out
}

struct embedding : Module {
    AutoGradTensor weight
    int num_embeddings
    int embedding_dim
    int padding_idx
}

func new_embedding(int num_embed, int embed_dim, int pad_idx) embedding {
    embedding layer
    layer.type_name = "embedding"
    layer.num_embeddings = num_embed
    layer.embedding_dim = embed_dim
    layer.padding_idx = pad_idx

    int[] shape = [num_embed, embed_dim]
    Tensor w_data = randn(shape, 0.0, 1.0)
    layer.weight = parameter(w_data, "weight")

    append(layer.parameters, layer.weight)
    layer
}

func forward(embedding self, int[] token_ids, int batch_size, int seq_len) AutoGradTensor {
    int num_tokens = batch_size * seq_len

    float[] emb_values = new float[num_tokens * self.embedding_dim]

    int i = 0
    while i < num_tokens {
        int token_id = token_ids[i]

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

struct LayerNorm : Module {
    AutoGradTensor gamma
    AutoGradTensor beta
    int[] normalized_shape
    float eps
}

func new_layer_norm(int[] norm_shape, float eps) LayerNorm {
    LayerNorm layer
    layer.type_name = "LayerNorm"
    layer.normalized_shape = norm_shape
    layer.eps = eps

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

func forward(LayerNorm self, AutoGradTensor x) AutoGradTensor {
    Tensor mean_val = mean(x.data, -1, true)
    Tensor centered = sub(x.data, mean_val)
    Tensor var_val = mean(square(centered.data), -1, true)
    Tensor std = sqrt(add_scalar(var_val, self.eps))
    Tensor normalized = div(centered.data, std)

    Tensor out_data = mul(normalized, self.gamma.data)
    out_data = add(out_data, self.beta.data)

    create_autograd_tensor(out_data, x.requires_grad)
}

struct MultiHeadAttention : Module {
    Linear q_proj
    Linear k_proj
    Linear v_proj
    Linear out_proj
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

func forward(MultiHeadAttention self, AutoGradTensor x, Tensor mask) AutoGradTensor {
    int batch_size = x.data.shape.dims[0]
    int seq_len = x.data.shape.dims[1]
    int d_model = self.embed_dim
    int n_heads = self.num_heads
    int d_k = self.head_dim

    AutoGradTensor Q = forward(self.q_proj, x)
    AutoGradTensor K = forward(self.k_proj, x)
    AutoGradTensor V = forward(self.v_proj, x)

    Q = autograd_view(Q, [batch_size, seq_len, n_heads, d_k])
    Q = autograd_transpose(Q, 1, 2)

    K = autograd_view(K, [batch_size, seq_len, n_heads, d_k])
    K = autograd_transpose(K, 1, 2)

    V = autograd_view(V, [batch_size, seq_len, n_heads, d_k])
    V = autograd_transpose(V, 1, 2)

    K_T = autograd_transpose(K, 2, 3)
    AutoGradTensor scores = autograd_matmul(Q, K_T)

    float scale = sqrt(d_k as float)
    AutoGradTensor scaled_scores = div(scores, scalar(scale))

    if self.causal {
        Tensor causal_mask = make_causal_mask(seq_len)
        scaled_scores = add(scaled_scores, causal_mask)
    }

    if mask != nil {
        scaled_scores = add(scaled_scores, mask)
    }

    AutoGradTensor attn_weights = softmax(scaled_scores, -1)

    if self.dropout_prob > 0 && self.training {
        attn_weights = tensor_dropout(attn_weights.data, self.dropout_prob, true)
        attn_weights = create_autograd_tensor(attn_weights, true)
    }

    AutoGradTensor context = autograd_matmul(attn_weights, V)

    context = autograd_transpose(context, 1, 2)
    context = autograd_view(context, [batch_size, seq_len, d_model])

    AutoGradTensor output = forward(self.out_proj, context)

    output
}

func make_causal_mask(int seq_len) Tensor {
    float[] vals = new float[seq_len * seq_len]
    int i = 0
    while i < seq_len {
        int j = 0
        while j < seq_len {
            if j > i { vals[i * seq_len + j] = NEG_INF }
            else { vals[i * seq_len + j] = 0.0 }
            j = j + 1
        }
        i = i + 1
    }
    Tensor { shape: [seq_len, seq_len], data: vals, device: "cpu", requires_grad: false }
}

struct FeedForward : Module {
    Linear fc1
    Linear fc2
    LayerNorm norm
    float dropout_prob
    string activation
}

func new_feed_forward(int d_model, int d_ff, float dropout_p, string act_fn) FeedForward {
    FeedForward ff
    ff.type_name = "FeedForward"
    ff.dropout_prob = dropout_p
    ff.activation = act_fn

    ff.fc1 = new_linear(d_model, d_ff, true)
    ff.fc2 = new_linear(d_ff, d_model, true)
    ff.norm = new_layer_norm([d_model], 1e-5)

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

func forward(FeedForward self, AutoGradTensor x) AutoGradTensor {
    AutoGradTensor h = forward(self.fc1, x)

    if self.activation == "relu" {
        h = autograd_relu(h)
    }
    else if self.activation == "gelu" {
        h = autograd_gelu(h)
    }
    else if self.activation == "silu" {
        h = autograd_silu(h)
    }

    if self.dropout_prob > 0 && self.training {
        h = tensor_dropout(h.data, self.dropout_prob, true)
        h = create_autograd_tensor(h, true)
    }

    AutoGradTensor output = forward(self.fc2, h)

    output
}

struct TransformerBlock : Module {
    MultiHeadAttention attn
    FeedForward ff_net
    LayerNorm norm1
    LayerNorm norm2
    float dropout_prob
    bool pre_norm
}

func new_transformer_block(int d_model, int n_heads, int d_ff, float dropout_p, bool pre_norm) TransformerBlock {
    TransformerBlock block
    block.type_name = "TransformerBlock"
    block.dropout_prob = dropout_p
    block.pre_norm = pre_norm

    block.attn = new_mha(d_model, n_heads, dropout_p, true)
    block.ff_net = new_feed_forward(d_model, d_ff, dropout_p, "gelu")
    block.norm1 = new_layer_norm([d_model], 1e-5)
    block.norm2 = new_layer_norm([d_model], 1e-5)

    block
}

func forward(TransformerBlock self, AutoGradTensor x) AutoGradTensor {
    if self.pre_norm {
        AutoGradTensor normed = forward(self.norm1, x)
        AutoGradTensor attn_out = forward(self.attn, normed, nil)

        AutoGradTensor h = add(x, attn_out)
        if self.dropout_prob > 0 {
            h = tensor_dropout(h.data, self.dropout_prob, true)
            h = create_autograd_tensor(h, true)
        }

        normed = forward(self.norm2, h)
        AutoGradTensor ff_out = forward(self.ff_net, normed)

        AutoGradTensor output = add(h, ff_out)
        if self.dropout_prob > 0 {
            output = tensor_dropout(output.data, self.dropout_prob, true)
            output = create_autograd_tensor(output, true)
        }

        output
    } else {
        AutoGradTensor attn_out = forward(self.attn, x, nil)
        AutoGradTensor h = add(x, attn_out)
        h = forward(self.norm1, h)

        AutoGradTensor ff_out = forward(self.ff_net, h)
        AutoGradTensor output = add(h, ff_out)
        output = forward(self.norm2, output)

        output
    }
}

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

struct Softmax : Module {
    int dim
}
func new_softmax(int d) Softmax { Softmax { dim: d } }
func forward(Softmax self, AutoGradTensor x) AutoGradTensor { autograd_softmax(x, self.dim) }

struct Sequential : Module {
    Module[] layers
}

func new_sequential(Module[] layers) Sequential {
    Sequential { layers: layers }
}

func forward(Sequential self, AutoGradTensor x) AutoGradTensor {
    AutoGradTensor output = x
    int i = 0
    while i < len(self.layers) {
        output = forward(self.layers[i], output)
        i = i + 1
    }
    output
}

func add_layer(Sequential mut self, Module layer) void {
    append(self.layers, layer)
}

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

func print_module_summary(Module m, string indent) void {
    println(indent, m.type_name, "(", m.name, ")")
    println(indent, "  Parameters: ", count_parameters(m))

    if m.type_name == "Sequential" {
        Sequential seq = m as Sequential
        int i = 0
        while i < len(seq.layers) {
            print_module_summary(seq.layers[i], indent + "  ")
            i = i + 1
        }
    }
}

func count_trainable_params(Module m) int {
    int total = 0
    int i = 0
    while i < len(m.parameters):
        if m.parameters[i].requires_grad:
            total = total + m.parameters[i].data.shape.size
        i = i + 1
    total
}

func to_device(Module mut m, string device) void {
}
