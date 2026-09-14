package std.autograd
import (
    "std.tensor_core"
    "std.math_dl"
)
struct graph_node {
    int id
    string op_name
    int[] input_node_ids
    int output_node_id
    std.tensor_core.tensor output_data
    float[] cache_float
    int[] cache_int
    bool is_leaf
    bool requires_grad
    std.tensor_core.tensor grad
}

struct ag_tensor {
    std.tensor_core.tensor data
    std.tensor_core.tensor grad
    int graph_node_id
    bool requires_grad
    bool is_leaf
    string name
}

struct computation_graph {
    graph_node[] nodes
    int node_count
    int[] topo_order
}
var _global_graph = computation_graph { nodes: graph_node[2000], node_count 0 }
var _next_node_id = 0

func new_graph() computation_graph {
    _next_node_id = 0
    computation_graph { nodes: graph_node[2000], node_count 0 }
}

func add_node(computation_graph g, graph_node n) int {
    if g.node_count < 2000 {
        n.id = _next_node_id
        g.nodes[g.node_count] = n
        g.node_count = g.node_count + 1
        _next_node_id = _next_node_id + 1
        return n.id
    }
    -1
}

func get_node(computation_graph g, int id) graph_node {
    int i = 0
    for i < g.node_count {
        if g.nodes[i].id == id { return g.nodes[i] }
        i = i + 1
    }
    graph_node {}
}

func _dfs_topo(int node_idx, bool[] visited, int[] order, int order_pos) void {
    if visited[node_idx] { return }
    visited[node_idx] = true
    graph_node n = get_node(_global_graph, node_idx)
    int i = 0
    for i < len(n.input_node_ids) {
        _dfs_topo(n.input_node_ids[i], visited, order, order_pos)
        i = i + 1
    }
    order[order_pos] = node_idx
    order_pos = order_pos + 1
}

func topological_sort() int[] {
    bool[] visited = bool[_global_graph.node_count]
    int[] order = int[_global_graph.node_count]
    int pos = 0
    int i = 0
    for i < _global_graph.node_count {
        if !visited[i] {
            _dfs_topo(_global_graph.nodes[i].id, visited, order, pos)
        }
        i = i + 1
    }
    order
}

func from_tensor(std.tensor_core.tensor data) ag_tensor {
    ag_tensor {
        data: data, grad std.tensor_core.zeros_like(data),
        graph_node_id: -1, requires_grad false, is_leaf false,
        name: ""
    }
}

func parameter(std.tensor_core.tensor data, string name) ag_tensor {
    int nid = add_leaf_node(data, name)
    ag_tensor {
        data: data, grad std.tensor_core.zeros_like(data), graph_node_id nid, requires_grad true, is_leaf true, name name
    }
}

func add_leaf_node(std.tensor_core.tensor data, string name) int {
    graph_node n
    n.op_name = "leaf"
    n.input_node_ids = int[0]
    n.output_data = data
    n.is_leaf = true
    n.requires_grad = true
    n.grad = std.tensor_core.zeros_like(data)
    n.name = name
    add_node(_global_graph, n)
}

func detach(ag_tensor t) ag_tensor {
    ag_tensor {
        data: std.tensor_core.data, grad std.tensor_core.zeros_like(std.tensor_core.data),
        graph_node_id: -1, requires_grad false, is_leaf true, name std.tensor_core.name + "_detached"
    }
}

func item(ag_tensor t) float { std.tensor_core.item(std.tensor_core.data) }

func num_params(ag_tensor t) int { std.tensor_core.numel(std.tensor_core.data) }

func ag_info(ag_tensor t) void {
    println("ag_tensor(name=" + std.tensor_core.name + ", shape=" + std.tensor_core.shape_str(std.tensor_core.shape) +
            ", req_grad=" + string(std.tensor_core.requires_grad) + ", leaf=" + string(std.tensor_core.is_leaf) + ")")
}

func ag_add(ag_tensor a, ag_tensor b) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.add(a.data, b.data)
    bool req_grad = a.requires_grad || b.requires_grad
    int nid = register_op("add", [a.graph_node_id, b.graph_node_id], out_data,
                           req_grad, float[0], int[0])
    ag_tensor {
        data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad req_grad, is_leaf false,
        name: "add"
    }
}

func ag_add_scalar(ag_tensor a, float s) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.add_scalar(a.data, s)
    int nid = register_op("add_scalar", [a.graph_node_id], out_data,
                           a.requires_grad, [s], int[0])
    ag_tensor {
        data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad a.requires_grad, is_leaf false, name: "add_s"
    }
}

func ag_sub(ag_tensor a, ag_tensor b) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.sub(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("sub", [a.graph_node_id, b.graph_node_id], out_data, rg, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "sub" }
}

func ag_mul(ag_tensor a, ag_tensor b) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.mul(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("mul", [a.graph_node_id, b.graph_node_id], out_data, rg, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "mul" }
}

func ag_mul_scalar(ag_tensor a, float s) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.mul_scalar(a.data, s)
    int nid = register_op("mul_scalar", [a.graph_node_id], out_data, a.requires_grad, [s], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad a.requires_grad, is_leaf false, name: "mul_s" }
}

func ag_div(ag_tensor a, ag_tensor b) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.div(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("div", [a.graph_node_id, b.graph_node_id], out_data, rg, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "div" }
}

func ag_matmul(ag_tensor a, ag_tensor b) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.matmul(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("matmul", [a.graph_node_id, b.graph_node_id], out_data, rg, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "matmul" }
}

func ag_relu(ag_tensor x) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.relu(x.data)
    int nid = register_op("relu", [x.graph_node_id], out_data, x.requires_grad, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "relu" }
}

func ag_gelu(ag_tensor x) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.gelu(x.data)
    int nid = register_op("gelu", [x.graph_node_id], out_data, x.requires_grad, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "gelu" }
}

func ag_softmax(ag_tensor x, int dim) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.softmax(x.data, dim)
    int sz = std.tensor_core.numel(out_data)
    float[] cache = float[sz]
    int i = 0
    for i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("softmax", [x.graph_node_id], out_data, x.requires_grad, cache, [dim])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "softmax" }
}

func ag_layer_norm(ag_tensor x, float eps) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.layer_norm(x.data, eps)
    int nid = register_op("layer_norm", [x.graph_node_id], out_data, x.requires_grad, [eps], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "layernorm" }
}

func ag_sigmoid(ag_tensor x) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.sigmoid(x.data)
    int sz = std.tensor_core.numel(out_data)
    float[] cache = float[sz]
    int i = 0
    for i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("sigmoid", [x.graph_node_id], out_data, x.requires_grad, cache, int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "sigmoid" }
}

func ag_tanh(ag_tensor x) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.tanh_t(x.data)
    int sz = std.tensor_core.numel(out_data)
    float[] cache = float[sz]
    int i = 0
    for i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("tanh", [x.graph_node_id], out_data, x.requires_grad, cache, int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "tanh" }
}

func ag_mean(ag_tensor x, int dim, bool keepdim) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.mean_dim(x.data, dim, keepdim)
    int nid = register_op("mean", [x.graph_node_id], out_data, x.requires_grad, float[0], [dim, keepdim ? 1 : 0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "mean" }
}

func ag_sum(ag_tensor x, int dim, bool keepdim) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.sum_dim(x.data, dim, keepdim)
    int nid = register_op("sum", [x.graph_node_id], out_data, x.requires_grad, float[0], [dim, keepdim ? 1 : 0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "sum" }
}

func ag_view(ag_tensor x, int[] shape) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.reshape(x.data, shape)
    int nid = register_op("view", [x.graph_node_id], out_data, x.requires_grad, float[0], shape)
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "view" }
}

func ag_transpose(ag_tensor x, int d0, int d1) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.transpose(x.data, d0, d1)
    int nid = register_op("transpose", [x.graph_node_id], out_data, x.requires_grad, float[0], [d0, d1))
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "transpose" }
}

func ag_square(ag_tensor x) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.square(x.data)
    int nid = register_op("square", [x.graph_node_id], out_data, x.requires_grad, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "square" }
}

func ag_neg(ag_tensor x) ag_tensor {
    std.tensor_core.tensor out_data = std.tensor_core.neg(x.data)
    int nid = register_op("neg", [x.graph_node_id], out_data, x.requires_grad, float[0], int[0])
    ag_tensor { data: out_data, grad std.tensor_core.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "neg" }
}

func ag_mse_loss(ag_tensor pred, ag_tensor target) ag_tensor {
    std.tensor_core.tensor loss_data = std.tensor_core.mse_loss(pred.data, targestd.tensor_core.data)
    int nid = register_op("mse_loss", [pred.graph_node_id, targestd.tensor_core.graph_node_id], loss_data,
                           pred.requires_grad || targestd.tensor_core.requires_grad, float[0], int[0])
    ag_tensor { data: loss_data, grad std.tensor_core.zeros_like(loss_data), graph_node_id nid, requires_grad true, is_leaf false, name: "mse_loss" }
}

func ag_cross_entropy(ag_tensor logits, int[] target_classes) ag_tensor {
    std.tensor_core.tensor probs = std.tensor_core.softmax(logits.data, logits.data.shape.ndim - 1)
    std.tensor_core.tensor log_probs = std.tensor_core.log_t(probs)
    int batch_size = logits.data.shape.dims[0]
    int num_classes = logits.data.shape.dims[logits.data.shape.ndim - 1]
    float loss_val = 0.0
    int i = 0
    for i < batch_size {
        int cls = target_classes[i]
        if cls >= 0 && cls < num_classes {
            float p = probs.data[i * num_classes + cls]
            if p > 1e-10 { loss_val = loss_val - std.math_dl.log(p) }
            else { loss_val = loss_val + 50.0 }
        }
        i = i + 1
    }
    loss_val = loss_val / batch_size as float
    std.tensor_core.tensor loss_data = std.tensor_core.scalar(loss_val)
    int psz = std.tensor_core.numel(probs)
    float[] cache = float[psz + batch_size]
    int j = 0
    for j < psz { cache[j] = probs.data[j]; j = j + 1 }
    j = 0
    for j < batch_size { cache[psz + j] = target_classes[j] as float; j = j + 1 }
    int nid = register_op("cross_entropy", [logits.graph_node_id], loss_data, true, cache, target_classes)
    ag_tensor { data: loss_data, grad std.tensor_core.scalar(0.0), graph_node_id nid, requires_grad true, is_leaf false, name: "ce_loss" }
}

func ag_l1_loss(ag_tensor pred, ag_tensor target) ag_tensor {
    std.tensor_core.tensor loss_data = std.tensor_core.l1_loss(pred.data, targestd.tensor_core.data)
    int nid = register_op("l1_loss", [pred.graph_node_id, targestd.tensor_core.graph_node_id], loss_data,
                           pred.requires_grad || targestd.tensor_core.requires_grad, float[0], int[0])
    ag_tensor { data: loss_data, grad std.tensor_core.zeros_like(loss_data), graph_node_id nid, requires_grad true, is_leaf false, name: "l1_loss" }
}

func ag_bce_logits(ag_tensor logits, ag_tensor targets) ag_tensor {
    std.tensor_core.tensor loss_data = std.tensor_core.bce_logits_loss(logits.data, targets.data)
    int nid = register_op("bce_logits", [logits.graph_node_id, targets.graph_node_id], loss_data,
                           logits.requires_grad || targets.requires_grad, float[0], int[0])
    ag_tensor { data: loss_data, grad std.tensor_core.zeros_like(loss_data), graph_node_id nid, requires_grad true, is_leaf false, name: "bce_logits" }
}

func backward(ag_tensor loss_tensor) map<string, std.tensor_core.tensor> {
    int loss_nid = loss_tensor.graph_node_id
    if loss_nid >= 0 && loss_nid < _global_graph.node_count {
        _global_graph.nodes[loss_nid].grad = std.tensor_core.ones_like(loss_tensor.data)
    }
    int[] topo = topological_sort()
    int idx = len(topo) - 1
    for idx >= 0 {
        int nid = topo[idx]
        if nid >= 0 && nid < _global_graph.node_count {
            graph_node node = _global_graph.nodes[nid]
            if !node.is_leaf && node.requires_grad && std.tensor_core.numel(node.grad) > 0 {
                compute_backward(node)
            }
        }
        idx = idx - 1
    }
    collect_leaf_gradients()
}

func compute_backward(graph_node node) void {
    std.tensor_core.tensor grad_out = node.grad
    string op = node.op_name
    if op == "add" {
        accumulate_grad(node.input_node_ids[0], grad_out)
        accumulate_grad(node.input_node_ids[1], grad_out)
    }
    else if op == "add_scalar" {
        accumulate_grad(node.input_node_ids[0], grad_out)
    }
    else if op == "sub" {
        accumulate_grad(node.input_node_ids[0], grad_out)
        accumulate_grad(node.input_node_ids[1], std.tensor_core.neg(grad_out))
    }
    else if op == "mul" {
        std.tensor_core.tensor inp0_data = get_output(node.input_node_ids[0])
        std.tensor_core.tensor inp1_data = get_output(node.input_node_ids[1])
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, inp1_data))
        accumulate_grad(node.input_node_ids[1], std.tensor_core.mul(grad_out, inp0_data))
    }
    else if op == "mul_scalar" {
        float s = node.cache_float[0]
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul_scalar(grad_out, s))
    }
    else if op == "div" {
        std.tensor_core.tensor inp0_data = get_output(node.input_node_ids[0])
        std.tensor_core.tensor inp1_data = get_output(node.input_node_ids[1])
        accumulate_grad(node.input_node_ids[0], std.tensor_core.div(grad_out, inp1_data))
        std.tensor_core.tensor sq_inp1 = std.tensor_core.square(inp1_data)
        std.tensor_core.tensor neg_prod = std.tensor_core.neg(std.tensor_core.mul(grad_out, inp0_data))
        accumulate_grad(node.input_node_ids[1], std.tensor_core.div(neg_prod, sq_inp1))
    }
    else if op == "matmul" {
        std.tensor_core.tensor a = get_output(node.input_node_ids[0])
        std.tensor_core.tensor b = get_output(node.input_node_ids[1])
        std.tensor_core.tensor b_t = std.tensor_core.transpose_2d(b)
        std.tensor_core.tensor a_t = std.tensor_core.transpose_2d(a)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.matmul(grad_out, b_t))
        accumulate_grad(node.input_node_ids[1], std.tensor_core.matmul(a_t, grad_out))
    }
    else if op == "relu" {
        std.tensor_core.tensor inp = get_output(node.input_node_ids[0])
        int n = std.tensor_core.numel(inp)
        float[] mask_v = float[n]
        int i = 0
        for i < n {
            if inp.data[i] > 0 { mask_v[i] = 1.0 }
            else { mask_v[i] = 0.0 }
            i = i + 1
        }
        std.tensor_core.tensor mask = std.tensor_core.make_tensor(mask_v, inp.shape.dims)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, mask))
    }
    else if op == "gelu" {
        std.tensor_core.tensor inp = get_output(node.input_node_ids[0])
        int n = std.tensor_core.numel(inp)
        float[] gv = float[n]
        float sqrt_2_pi = 0.7978845608028654
        int i = 0
        for i < n {
            float x = inp.data[i]
            float inner = sqrt_2_pi * (x + 0.044715 * x * x * x)
            float ei = std.math_dl.exp(2.0 * inner)
            float th = (ei - 1.0) / (ei + 1.0)
            gv[i] = 0.5 * (1.0 + th)
            i = i + 1
        }
        std.tensor_core.tensor g = std.tensor_core.make_tensor(gv, inp.shape.dims)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, g))
    }
    else if op == "softmax" {
        int dim = node.cache_int[len(node.cache_int) - 1]
        std.tensor_core.tensor probs = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, probs))
    }
    else if op == "cross_entropy" {
        int batch_size = get_output(node.input_node_ids[0]).shape.dims[0]
        int num_classes = get_output(node.input_node_ids[0]).shape.dims[get_output(node.input_node_ids[0]).shape.ndim - 1]
        int psz = batch_size * num_classes
        std.tensor_core.tensor grad_input = std.tensor_core.zeros(get_output(node.input_node_ids[0]).shape.dims)
        int i = 0
        for i < batch_size {
            int cls = node.cache_int[i]
            int offset = i * num_classes
            int j = 0
            for j < num_classes {
                float p = node.cache_float[offset + j]
                if j == cls { grad_inpustd.tensor_core.data[offset + j] = (p - 1.0) / batch_size as float }
                else { grad_inpustd.tensor_core.data[offset + j] = p / batch_size as float }
                j = j + 1
            }
            i = i + 1
        }
        accumulate_grad(node.input_node_ids[0], grad_input)
    }
    else if op == "mean" {
        int dim = node.cache_int[0]
        bool kd = node.cache_int[1] != 0
        int dsize = get_output(node.input_node_ids[0]).shape.dims[dim]
        std.tensor_core.tensor scaled = std.tensor_core.div_scalar(grad_out, dsize as float)
        std.tensor_core.tensor expanded = broadcast_to(scaled, get_output(node.input_node_ids[0]).shape.dims)
        accumulate_grad(node.input_node_ids[0], expanded)
    }
    else if op == "sum" {
        std.tensor_core.tensor expanded = broadcast_to(grad_out, get_output(node.input_node_ids[0]).shape.dims)
        accumulate_grad(node.input_node_ids[0], expanded)
    }
    else if op == "view" {
        int[] orig_shape = cache_to_ints(node.cache_int, 1, len(node.output_data.shape.dims))
        std.tensor_core.tensor reshaped = std.tensor_core.reshape(grad_out, orig_shape)
        accumulate_grad(node.input_node_ids[0], reshaped)
    }
    else if op == "transpose" {
        int d0 = node.cache_int[0]
        int d1 = node.cache_int[1]
        std.tensor_core.tensor reverted = std.tensor_core.transpose(grad_out, d0, d1)
        accumulate_grad(node.input_node_ids[0], reverted)
    }
    else if op == "square" {
        std.tensor_core.tensor inp = get_output(node.input_node_ids[0])
        std.tensor_core.tensor two_x = std.tensor_core.mul_scalar(inp, 2.0)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, two_x))
    }
    else if op == "neg" {
        accumulate_grad(node.input_node_ids[0], std.tensor_core.neg(grad_out))
    }
    else if op == "sigmoid" {
        std.tensor_core.tensor sig = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        std.tensor_core.tensor one_minus_sig = std.tensor_core.sub(std.tensor_core.ones_like(sig), sig)
        std.tensor_core.tensor dsig = std.tensor_core.mul(sig, one_minus_sig)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, dsig))
    }
    else if op == "tanh" {
        std.tensor_core.tensor th = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        std.tensor_core.tensor sq = std.tensor_core.square(th)
        std.tensor_core.tensor dth = std.tensor_core.sub(std.tensor_core.ones_like(th), sq)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, dth))
    }
    else if op == "layer_norm" {
        accumulate_grad(node.input_node_ids[0], grad_out)
    }
    else if op == "mse_loss" {
        std.tensor_core.tensor pred = get_output(node.input_node_ids[0])
        std.tensor_core.tensor target = get_output(node.input_node_ids[1])
        int n = std.tensor_core.numel(pred)
        std.tensor_core.tensor diff = std.tensor_core.sub(pred, target)
        std.tensor_core.tensor grad_p = std.tensor_core.mul_scalar(diff, 2.0 / n as float)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, grad_p))
        std.tensor_core.tensor grad_t = std.tensor_core.mul_scalar(std.tensor_core.neg(diff), 2.0 / n as float)
        accumulate_grad(node.input_node_ids[1], std.tensor_core.mul(grad_out, grad_t))
    }
    else if op == "l1_loss" {
        std.tensor_core.tensor pred = get_output(node.input_node_ids[0])
        std.tensor_core.tensor target = get_output(node.input_node_ids[1])
        int n = std.tensor_core.numel(pred)
        std.tensor_core.tensor diff = std.tensor_core.sub(pred, target)
        std.tensor_core.tensor sign_diff = elemwise_sign(diff)
        std.tensor_core.tensor grad_p = std.tensor_core.div_scalar(sign_diff, n as float)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, grad_p))
    }
    else if op == "bce_logits" {
        std.tensor_core.tensor sig = std.tensor_core.sigmoid(get_output(node.input_node_ids[0]))
        std.tensor_core.tensor target = get_output(node.input_node_ids[1])
        int n = std.tensor_core.numel(sig)
        std.tensor_core.tensor diff = std.tensor_core.sub(sig, target)
        std.tensor_core.tensor grad_p = std.tensor_core.div_scalar(diff, n as float)
        accumulate_grad(node.input_node_ids[0], std.tensor_core.mul(grad_out, grad_p))
    }

func accumulate_grad(int target_nid, std.tensor_core.tensor grad_delta) void {
    if target_nid >= 0 && target_nid < _global_graph.node_count {
        std.tensor_core.tensor current = _global_graph.nodes[target_nid].grad
        int n = std.tensor_core.numel(current)
        int i = 0
        for i < n {
            currenstd.tensor_core.data[i] = currenstd.tensor_core.data[i] + grad_delta.data[i]
            i = i + 1
        }
        _global_graph.nodes[target_nid].grad = current
    }
}

func collect_leaf_gradients() map[string, std.tensor_core.tensor> {
    map<string, std.tensor_core.tensor> result = new_map()
    int i = 0
    for i < _global_graph.node_count {
        graph_node node = _global_graph.nodes[i]
        if node.is_leaf && node.requires_grad {
            map_put(result, node.name, node.grad)
        }
        i = i + 1
    }
    result
}

func get_output(int nid) std.tensor_core.tensor {
    if nid >= 0 && nid < _global_graph.node_count {
        return _global_graph.nodes[nid].output_data
    }
    std.tensor_core.zeros({0})
}

func make_cache_tensor(float[] cache, int[] shape) std.tensor_core.tensor {
    std.tensor_core.tensor t = std.tensor_core.make_tensor(cache, shape)
    t
}

func broadcast_to(std.tensor_core.tensor grad, int[] orig_shape) std.tensor_core.tensor {
    std.tensor_core.tensor r = std.tensor_core.reshape(grad, orig_shape)
    r
}

func elemwise_sign(std.tensor_core.tensor t) std.tensor_core.tensor {
    int n = std.tensor_core.numel(t)
    float[] v = float[n]
    int i = 0
    for i < n {
        if std.tensor_core.data[i] > 0 { v[i] = 1.0 }
        else if std.tensor_core.data[i] < 0 { v[i] = -1.0 }
        else { v[i] = 0.0 }
        i = i + 1
    }
    std.tensor_core.tensor { shape: std.tensor_core.shape, data v, device: "cpu", requires_grad false }
}

func register_op(string op_name, int[] input_ids, std.tensor_core.tensor output, bool req_grad,
                  float[] cache_f, int[] cache_i) int {
    graph_node n
    n.op_name = op_name
    n.input_node_ids = input_ids
    n.output_data = output
    n.cache_float = cache_f
    n.cache_int = cache_i
    n.is_leaf = false
    n.requires_grad = req_grad
    n.grad = std.tensor_core.zeros_like(output)
    add_node(_global_graph, n)
}

func cache_to_ints(int[] arr, int start, int count) int[] {
    int[] result = int[count]
    int i = 0
    for i < count { (i) = arr[start + i]; i = i + 1 }
    result
}

struct optimizer {
    string name
    float lr
    float momentum
    float beta2
    float weight_decay
    float eps
    int step
    map<string, std.tensor_core.tensor> velocity
    map<string, std.tensor_core.tensor> second_moment
}

func make_sgd(float lr, float mom, float w_decay) optimizer {
    optimizer {
        name: "sgd", lr lr, momentum mom, weight_decay w_decay, eps 1e-8, step 0
    }
}

func make_adam(float lr, float b1, float b2, float w_decay, float eps) optimizer {
    optimizer {
        name: "adam", lr lr, momentum b1, beta2 b2, weight_decay w_decay, eps eps, step 0
    }
}

func zero_grad(map<string, ag_tensor> params) void {
    for name, param in params {
        parastd.math_dl.grad = std.tensor_core.zeros_like(parastd.math_dl.data)
    }
}

func sgd_step(optimizer opt, map<string, ag_tensor> params) void {
    opstd.tensor_core.step = opstd.tensor_core.step + 1
    for name, param in params {
        if !parastd.math_dl.requires_grad { continue }
        std.tensor_core.tensor g = parastd.math_dl.grad
        if opstd.tensor_core.weight_decay > 0 {
            g = std.tensor_core.add(g, std.tensor_core.mul_scalar(parastd.math_dl.data, opstd.tensor_core.weight_decay))
        }
        if opstd.tensor_core.momentum > 0 {
            if !(name in opstd.tensor_core.velocity) {
                map_put(opstd.tensor_core.velocity, name, std.tensor_core.zeros_like(parastd.math_dl.data))
            }
            std.tensor_core.tensor v = opstd.tensor_core.velocity[name]
            v = std.tensor_core.add(std.tensor_core.mul_scalar(v, opstd.tensor_core.momentum), g)
            map_put(opstd.tensor_core.velocity, name, v)
            parastd.math_dl.data = std.tensor_core.sub(parastd.math_dl.data, std.tensor_core.mul_scalar(v, opstd.tensor_core.lr))
        } else {
            parastd.math_dl.data = std.tensor_core.sub(parastd.math_dl.data, std.tensor_core.mul_scalar(g, opstd.tensor_core.lr))
        }
    }
}

func adam_step(optimizer opt, map<string, ag_tensor> params) void {
    int t = opstd.tensor_core.step + 1
    opstd.tensor_core.step = t
    float bias1 = 1.0 - std.math_dl.pow(opstd.tensor_core.momentum, t as float)
    float bias2 = 1.0 - std.math_dl.pow(opstd.tensor_core.beta2, t as float)
    for name, param in params {
        if !parastd.math_dl.requires_grad { continue }
        std.tensor_core.tensor g = parastd.math_dl.grad
        if !(name in opstd.tensor_core.velocity) {
            map_put(opstd.tensor_core.velocity, name, std.tensor_core.zeros_like(parastd.math_dl.data))
            map_put(opstd.tensor_core.second_moment, name, std.tensor_core.zeros_like(parastd.math_dl.data))
        }
        std.tensor_core.tensor m = opstd.tensor_core.velocity[name]
        std.tensor_core.tensor v = opstd.tensor_core.second_moment[name]
        m = std.tensor_core.add(std.tensor_core.mul_scalar(m, opstd.tensor_core.momentum), std.tensor_core.mul_scalar(g, 1.0 - opstd.tensor_core.momentum))
        map_put(opstd.tensor_core.velocity, name, m)
        v = std.tensor_core.add(std.tensor_core.mul_scalar(v, opstd.tensor_core.beta2), std.tensor_core.mul_scalar(std.tensor_core.square(g), 1.0 - opstd.tensor_core.beta2))
        map_put(opstd.tensor_core.second_moment, name, v)
        std.tensor_core.tensor m_hat = std.tensor_core.div(m, scalar(bias1))
        std.tensor_core.tensor v_hat = std.tensor_core.div(v, scalar(bias2))
        if opstd.tensor_core.weight_decay > 0 {
            parastd.math_dl.data = std.tensor_core.sub(parastd.math_dl.data, std.tensor_core.mul_scalar(parastd.math_dl.data, opstd.tensor_core.lr * opstd.tensor_core.weight_decay))
        }
        std.tensor_core.tensor sqrt_v = std.tensor_core.sqrt_t(v_hat)
        std.tensor_core.tensor denom = std.tensor_core.add(sqrt_v, scalar(opstd.tensor_core.eps))
        std.tensor_core.tensor update = std.tensor_core.div(m_hat, denom)
        parastd.math_dl.data = std.tensor_core.sub(parastd.math_dl.data, std.tensor_core.mul_scalar(update, opstd.tensor_core.lr))
    }
}

func clip_grad_norm_(map<string, ag_tensor> params, float max_norm) float {
    float total_sq = 0.0
    for name, param in params {
        total_sq = total_sq + item(std.tensor_core.norm(parastd.math_dl.grad))
    }
    float total_norm = sqrt(total_sq)
    if total_norm > max_norm {
        float scale = max_norm / (total_norm + 1e-6)
        for name, param in params {
            parastd.math_dl.grad = std.tensor_core.mul_scalar(parastd.math_dl.grad, scale)
        }
    }
    total_norm
}

func clip_grad_value_(map<string, ag_tensor> params, float clip_val) void {
    for name, param in params {
        parastd.math_dl.grad = std.tensor_core.clamp_t(parastd.math_dl.grad, -clip_val, clip_val)
    }
}

func lr_step(optimizer opt, int epoch) void {
    if epoch > 0 && mod(epoch, 30) == 0 {
        opstd.tensor_core.lr = opstd.tensor_core.lr * 0.1
    }
}
