package std.ai.autograd

use std.tensor.{Tensor, TensorShape, scalar, zeros, add, sub, mul, div, matmul_2d, reshape}
use std.math.{exp as math_exp, log as math_log, tanh as math_tanh}

struct GradContext {
    bool needs_grad
    string op_name
    Tensor[] inputs
    Tensor output
    func backward_fn

    float[] cache_floats
    int[] cache_ints
    bool[] cache_bools
}

struct AutoGradTensor {
    Tensor data
    Tensor grad
    GradContext grad_ctx
    bool requires_grad
}

var current_graph = new GradNode[1000]
var graph_size = 0

func start_graph() void {
    graph_size = 0
}

func end_graph() int {
    graph_size
}

func add_to_graph(GradNode node) int {
    if graph_size < 1000 {
        current_graph[graph_size] = node
        graph_size = graph_size + 1
    }
    graph_size - 1
}

func topological_sort(int root_idx) int[] {
    bool[] visited = new bool[graph_size]
    int[] order = new int[graph_size]
    int order_len = 0

    dfs_visit(root_idx, visited, order, order_len)
    order
}

func dfs_visit(int idx, bool[] visited, int[] order, int order_len_ref) void {
    if visited[idx] { return }
    visited[idx] = true

    GradNode node = current_graph[idx]
    int i = 0
    while i < len(node.inputs) {
        dfs_visit(node.inputs[i], visited, order, order_len_ref)
        i = i + 1
    }

    order[order_len_ref] = idx
    order_len_ref = order_len_ref + 1
}

func backward(AutoGradTensor loss_tensor) Map<string, Tensor> {
    loss_tensor.grad = ones_like(loss_tensor.data)

    int[] topo_order = topological_sort(loss_tensor.grad_ctx.graph_idx)

    int i = len(topo_order) - 1
    while i >= 0 {
        int node_idx = topo_order[i]
        GradNode node = current_graph[node_idx]

        if node.backward_fn != nil && node.grad_output != nil {
            Tensor[] input_grads = call_backward(node, node.grad_output)

            int j = 0
            while j < len(input_grads) {
                int inp_idx = node.inputs[j]
                if inp_idx < graph_size && current_graph[inp_idx].grad != nil {
                    current_graph[inp_idx].grad = add(current_graph[inp_idx].grad, input_grads[j])
                }
                j = j + 1
            }
        }

        i = i - 1
    }

    return collect_leaf_gradients()
}

func collect_leaf_gradients() Map<string, Tensor> {
    Map<string, Tensor> result = new_map()

    int i = 0
    while i < graph_size {
        GradNode node = current_graph[i]
        if node.is_leaf && node.requires_grad && node.grad != nil {
            map_put(result, node.name, node.grad)
        }
        i = i + 1
    }

    result
}

func autograd_add(AutoGradTensor a, AutoGradTensor b) AutoGradTensor {
    Tensor out_data = add(a.data, b.data)

    AutoGradTensor result = create_autograd_tensor(out_data, a.requires_grad || b.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "add"
        ctx.inputs = [a.grad_ctx.graph_idx, b.grad_ctx.graph_idx]
        ctx.output = result

        ctx.backward_fn = func(Tensor grad_out) Tensor[] {
            [grad_out, grad_out]
        }

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_mul(AutoGradTensor a, AutoGradTensor b) AutoGradTensor {
    Tensor out_data = mul(a.data, b.data)

    AutoGradTensor result = create_autograd_tensor(out_data, a.requires_grad || b.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "mul"
        ctx.inputs = [a.grad_ctx.graph_idx, b.grad_ctx.graph_idx]
        ctx.output = result

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            mul(grad_out, b.data),
            mul(grad_out, a.data),
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_matmul(AutoGradTensor a, AutoGradTensor b) AutoGradTensor {
    Tensor out_data = matmul_2d(a.data, b.data)

    AutoGradTensor result = create_autograd_tensor(out_data, a.requires_grad || b.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "matmul"
        ctx.inputs = [a.grad_ctx.graph_idx, b.grad_ctx.graph_idx]
        ctx.output = result

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            matmul_2d(grad_out, transpose(b.data)),
            matmul_2d(transpose(a.data), grad_out),
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_relu(AutoGradTensor x) AutoGradTensor {
    Tensor out_data = relu(x.data)

    AutoGradTensor result = create_autograd_tensor(out_data, x.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "relu"
        ctx.inputs = [x.grad_ctx.graph_idx]
        ctx.output = result

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            mul(grad_out, relu_backward_mask(x.data))
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func relu_backward_mask(Tensor x) Tensor {
    float[] mask = new float[x.shape.size]
    int i = 0
    while i < x.shape.size {
        if x.data.values[i] > 0 { mask[i] = 1.0 }
        else { mask[i] = 0.0 }
        i = i + 1
    }
    Tensor { shape: x.shape, data: mask, device: "cpu", requires_grad: false }
}

func cross_entropy_loss(AutoGradTensor logits, int[] target_classes) AutoGradTensor {
    Tensor probs = softmax(logits.data)

    int batch_size = logits.shape.dims[0]
    float loss_val = 0.0

    int i = 0
    while i < batch_size {
        int cls = target_classes[i]
        if cls >= 0 && cls < probs.shape.dims[1] {
            float p = probs.data.values[i * probs.shape.dims[1] + cls]
            if p > 1e-10 { loss_val = loss_val - math_log(p) }
            else { loss_val = loss_val + 50.0 }
        }
        i = i + 1
    }

    loss_val = loss_val / batch_size as float
    Tensor loss_data = scalar(loss_val)

    AutoGradTensor result = create_autograd_tensor(loss_data, true)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "cross_entropy"
        ctx.inputs = [logits.grad_ctx.graph_idx]
        ctx.output = result
        ctx.cache_ints = target_classes

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            compute_ce_grad(probs, target_classes, batch_size)
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func compute_ce_grad(Tensor probs, int[] targets, int batch_size) Tensor {
    Tensor grad = zeros_like(probs)

    int i = 0
    while i < batch_size {
        int cls = targets[i]
        int offset = i * probs.shape.dims[1]
        int j = 0
        while j < probs.shape.dims[1] {
            float val = probs.data.values[offset + j]
            if j == cls { grad.data.values[offset + j] = (val - 1.0) / batch_size as float }
            else { grad.data.values[offset + j] = val / batch_size as float }
            j = j + 1
        }
        i = i + 1
    }

    grad
}

func mse_loss(AutoGradTensor pred, AutoGradTensor target) AutoGradTensor {
    Tensor diff = sub(pred.data, target.data)
    Tensor sq = square(diff)
    Tensor loss_data = mean(sq)

    AutoGradTensor result = create_autograd_tensor(loss_data, pred.requires_grad || target.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "mse"
        ctx.inputs = [pred.grad_ctx.graph_idx, target.grad_ctx.graph_idx]
        ctx.output = result

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            mul_scalar(mul(grad_out, diff), 2.0 / pred.data.shape.size as float),
            mul_scalar(mul(grad_out, neg(diff)), 2.0 / target.data.shape.size as float),
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_mean(AutoGradTensor x, int dim, bool keepdim) AutoGradTensor {
    Tensor out_data = mean(x.data, dim, keepdim)

    AutoGradTensor result = create_autograd_tensor(out_data, x.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "mean"
        ctx.inputs = [x.grad_ctx.graph_idx]
        ctx.output = result
        ctx.cache_ints = [dim, keepdim ? 1 : 0]

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            expand_to_shape(grad_out, x.data.shape) / x.data.shape[dim] as float
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_sum(AutoGradTensor x, int dim, bool keepdim) AutoGradTensor {
    Tensor out_data = sum(x.data, dim, keepdim)

    AutoGradTensor result = create_autograd_tensor(out_data, x.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "sum"
        ctx.inputs = [x.grad_ctx.graph_idx]
        ctx.output = result

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            expand_to_shape(grad_out, x.data.shape)
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_view(AutoGradTensor x, int[] shape) AutoGradTensor {
    Tensor out_data = view(x.data, shape)

    AutoGradTensor result = create_autograd_tensor(out_data, x.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "view"
        ctx.inputs = [x.grad_ctx.graph_idx]
        ctx.output = result
        ctx.cache_ints = shape

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            view(grad_out, x.data.shape.dims)
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

func autograd_transpose(AutoGradTensor x, int dim0, int dim1) AutoGradTensor {
    Tensor out_data = transpose(x.data, dim0, dim1)

    AutoGradTensor result = create_autograd_tensor(out_data, x.requires_grad)

    if result.requires_grad {
        GradContext ctx
        ctx.op_name = "transpose"
        ctx.inputs = [x.grad_ctx.graph_idx]
        ctx.output = result
        ctx.cache_ints = [dim0, dim1]

        ctx.backward_fn = func(Tensor grad_out) Tensor[] [
            transpose(grad_out, dim0, dim1)
        ]

        result.grad_ctx = ctx
        add_to_graph(make_node(ctx))
    }

    result
}

struct optimizer_state {
    string name
    float learning_rate
    float momentum
    float beta2
    float weight_decay
    float eps
    int step_count

    Map<string, Tensor> velocity
    Map<string, Tensor> second_moment
}

func new_sgd_optimizer(float lr, float momentum, float weight_decay) optimizer_state {
    optimizer_state {
        name: "sgd",
        learning_rate: lr,
        momentum: momentum,
        weight_decay: weight_decay,
        step_count: 0,
    }
}

func new_adam_optimizer(float lr, float beta1, float beta2, float weight_decay, float eps) optimizer_state {
    optimizer_state {
        name: "adam",
        learning_rate: lr,
        momentum: beta1,
        beta2: beta2,
        weight_decay: weight_decay,
        eps: eps,
        step_count: 0,
    }
}

func zero_grad(Map<string, AutoGradTensor> params) void {
    for name, param in params {
        param.grad = zeros(param.data.shape)
    }
}

func sgd_step(optimizer_state mut opt, Map<string, AutoGradTensor> params) void {
    opt.step_count = opt.step_count + 1

    for name, param in params {
        if !param.requires_grad { continue }

        Tensor g = param.grad
        if opt.weight_decay > 0 {
            g = g + opt.weight_decay * param.data
        }

        if opt.momentum > 0 {
            if !(name in opt.velocity) {
                opt.velocity[name] = zeros(param.data.shape)
            }
            opt.velocity[name] = opt.momentum * opt.velocity[name] + g
            param.data = param.data - opt.learning_rate * opt.velocity[name]
        } else {
            param.data = param.data - opt.learning_rate * g
        }
    }
}

func adam_step(optimizer_state mut opt, Map<string, AutoGradTensor> params) void {
    int t = opt.step_count + 1
    opt.step_count = t
    float bias_corr1 = 1.0 - pow(opt.momentum, t as float)
    float bias_corr2 = 1.0 - pow(opt.beta2, t as float)

    for name, param in params {
        if !param.requires_grad { continue }

        Tensor g = param.grad

        if !(name in opt.velocity) {
            opt.velocity[name] = zeros(param.data.shape)
            opt.second_moment[name] = zeros(param.data.shape)
        }

        opt.velocity[name] = opt.momentum * opt.velocity[name] + (1.0 - opt.momentum) * g
        opt.second_moment[name] = opt.beta2 * opt.second_moment[name] + (1.0 - opt.beta2) * square(g)

        Tensor m_hat = opt.velocity[name] / bias_corr1
        Tensor v_hat = opt.second_moment[name] / bias_corr2

        if opt.weight_decay > 0 {
            param.data = param.data - opt.learning_rate * opt.weight_decay * param.data
        }

        param.data = param.data - opt.learning_rate * m_hat / (sqrt(v_hat) + opt.eps)
    }
}

func lr_step(optimizer_state mut opt, string scheduler, int epoch) void {
    if scheduler == "step" && epoch % 30 == 0 {
        opt.learning_rate = opt.learning_rate * 0.1
    }
    else if scheduler == "cosine" {
        float progress = epoch as float / 100.0
        opt.learning_rate = opt.learning_rate * 0.5 * (1.0 + cos(PI * progress))
    }
}

func clip_grad_norm_(Map<string, AutoGradTensor> params, float max_norm) float {
    float total_norm_sq = 0.0
    for name, param in params {
        total_norm_sq = total_norm_sq + sum(square(param.grad)).item()
    }
    float total_norm = sqrt(total_norm_sq)

    if total_norm > max_norm {
        float scale = max_norm / (total_norm + 1e-6)
        for name, param in params {
            param.grad = param.grad * scale
        }
    }

    total_norm
}

func clip_grad_value_(Map<string, AutoGradTensor> params, float clip_value) void {
    for name, param in params {
        param.grad = clamp(param.grad, -clip_value, clip_value)
    }
}

func create_autograd_tensor(Tensor data, bool requires_grad) AutoGradTensor {
    AutoGradTensor {
        data: data,
        grad: zeros(data.shape),
        requires_grad: requires_grad,
    }
}

func parameter(Tensor data, string name) AutoGradTensor {
    AutoGradTensor t = create_autograd_tensor(data, true)
    t.name = name
    t.is_leaf = true
    t
}

func detach(AutoGradTensor t) AutoGradTensor {
    AutoGradTensor {
        data: t.data,
        grad: zeros(t.data.shape),
        requires_grad: false,
        is_leaf: true,
    }
}

func needs_grad(AutoGradTensor t) bool { t.requires_grad }

func num_parameters(AutoGradTensor t) int { t.data.shape.size }

func print_ag_info(AutoGradTensor t) void {
    println("AutoGradTensor(", t.name, ", shape=", shape_str(t.data.shape), 
            ", req_grad=", t.requires_grad, ", is_leaf=", t.is_leaf, ")")
}
