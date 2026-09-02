package std.autograd
use std.tensor_core as T
use std.math_dl as M
struct graph_node {
    int id
    string op_name
    int[] input_node_ids
    int output_node_id
    T.tensor output_data
    float[] cache_float
    int[] cache_int
    bool is_leaf
    bool requires_grad
    T.tensor grad
}

struct ag_tensor {
    T.tensor data
    T.tensor grad
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
var _global_graph = computation_graph { nodes: new graph_node[2000], node_count 0 }
var _next_node_id = 0

func new_graph() computation_graph {
    _next_node_id = 0
    computation_graph { nodes: new graph_node[2000], node_count 0 }
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
    bool[] visited = new bool[_global_graph.node_count]
    int[] order = new int[_global_graph.node_count]
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

func from_tensor(T.tensor data) ag_tensor {
    ag_tensor {
        data: data, grad T.zeros_like(data),
        graph_node_id: -1, requires_grad false, is_leaf false,
        name: ""
    }
}

func parameter(T.tensor data, string name) ag_tensor {
    int nid = add_leaf_node(data, name)
    ag_tensor {
        data: data, grad T.zeros_like(data), graph_node_id nid, requires_grad true, is_leaf true, name name
    }
}

func add_leaf_node(T.tensor data, string name) int {
    graph_node n
    n.op_name = "leaf"
    n.input_node_ids = new int[0]
    n.output_data = data
    n.is_leaf = true
    n.requires_grad = true
    n.grad = T.zeros_like(data)
    n.name = name
    add_node(_global_graph, n)
}

func detach(ag_tensor t) ag_tensor {
    ag_tensor {
        data: t.data, grad T.zeros_like(t.data),
        graph_node_id: -1, requires_grad false, is_leaf true, name t.name + "_detached"
    }
}

func item(ag_tensor t) float { T.item(t.data) }

func num_params(ag_tensor t) int { T.numel(t.data) }

func ag_info(ag_tensor t) void {
    println("ag_tensor(name=" + t.name + ", shape=" + T.shape_str(t.shape) +
            ", req_grad=" + string(t.requires_grad) + ", leaf=" + string(t.is_leaf) + ")")
}

func ag_add(ag_tensor a, ag_tensor b) ag_tensor {
    T.tensor out_data = T.add(a.data, b.data)
    bool req_grad = a.requires_grad || b.requires_grad
    int nid = register_op("add", [a.graph_node_id, b.graph_node_id], out_data,
                           req_grad, new float[0], new int[0])
    ag_tensor {
        data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad req_grad, is_leaf false,
        name: "add"
    }
}

func ag_add_scalar(ag_tensor a, float s) ag_tensor {
    T.tensor out_data = T.add_scalar(a.data, s)
    int nid = register_op("add_scalar", [a.graph_node_id], out_data,
                           a.requires_grad, [s], new int[0])
    ag_tensor {
        data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad a.requires_grad, is_leaf false, name: "add_s"
    }
}

func ag_sub(ag_tensor a, ag_tensor b) ag_tensor {
    T.tensor out_data = T.sub(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("sub", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "sub" }
}

func ag_mul(ag_tensor a, ag_tensor b) ag_tensor {
    T.tensor out_data = T.mul(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("mul", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "mul" }
}

func ag_mul_scalar(ag_tensor a, float s) ag_tensor {
    T.tensor out_data = T.mul_scalar(a.data, s)
    int nid = register_op("mul_scalar", [a.graph_node_id], out_data, a.requires_grad, [s], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad a.requires_grad, is_leaf false, name: "mul_s" }
}

func ag_div(ag_tensor a, ag_tensor b) ag_tensor {
    T.tensor out_data = T.div(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("div", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "div" }
}

func ag_matmul(ag_tensor a, ag_tensor b) ag_tensor {
    T.tensor out_data = T.matmul(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("matmul", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad rg, is_leaf false, name: "matmul" }
}

func ag_relu(ag_tensor x) ag_tensor {
    T.tensor out_data = T.relu(x.data)
    int nid = register_op("relu", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "relu" }
}

func ag_gelu(ag_tensor x) ag_tensor {
    T.tensor out_data = T.gelu(x.data)
    int nid = register_op("gelu", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "gelu" }
}

func ag_softmax(ag_tensor x, int dim) ag_tensor {
    T.tensor out_data = T.softmax(x.data, dim)
    int sz = T.numel(out_data)
    float[] cache = new float[sz]
    int i = 0
    for i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("softmax", [x.graph_node_id], out_data, x.requires_grad, cache, [dim])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "softmax" }
}

func ag_layer_norm(ag_tensor x, float eps) ag_tensor {
    T.tensor out_data = T.layer_norm(x.data, eps)
    int nid = register_op("layer_norm", [x.graph_node_id], out_data, x.requires_grad, [eps], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "layernorm" }
}

func ag_sigmoid(ag_tensor x) ag_tensor {
    T.tensor out_data = T.sigmoid(x.data)
    int sz = T.numel(out_data)
    float[] cache = new float[sz]
    int i = 0
    for i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("sigmoid", [x.graph_node_id], out_data, x.requires_grad, cache, new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "sigmoid" }
}

func ag_tanh(ag_tensor x) ag_tensor {
    T.tensor out_data = T.tanh_t(x.data)
    int sz = T.numel(out_data)
    float[] cache = new float[sz]
    int i = 0
    for i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("tanh", [x.graph_node_id], out_data, x.requires_grad, cache, new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "tanh" }
}

func ag_mean(ag_tensor x, int dim, bool keepdim) ag_tensor {
    T.tensor out_data = T.mean_dim(x.data, dim, keepdim)
    int nid = register_op("mean", [x.graph_node_id], out_data, x.requires_grad, new float[0], [dim, keepdim ? 1 : 0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "mean" }
}

func ag_sum(ag_tensor x, int dim, bool keepdim) ag_tensor {
    T.tensor out_data = T.sum_dim(x.data, dim, keepdim)
    int nid = register_op("sum", [x.graph_node_id], out_data, x.requires_grad, new float[0], [dim, keepdim ? 1 : 0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "sum" }
}

func ag_view(ag_tensor x, int[] shape) ag_tensor {
    T.tensor out_data = T.reshape(x.data, shape)
    int nid = register_op("view", [x.graph_node_id], out_data, x.requires_grad, new float[0], shape)
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "view" }
}

func ag_transpose(ag_tensor x, int d0, int d1) ag_tensor {
    T.tensor out_data = T.transpose(x.data, d0, d1)
    int nid = register_op("transpose", [x.graph_node_id], out_data, x.requires_grad, new float[0], [d0, d1))
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "transpose" }
}

func ag_square(ag_tensor x) ag_tensor {
    T.tensor out_data = T.square(x.data)
    int nid = register_op("square", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "square" }
}

func ag_neg(ag_tensor x) ag_tensor {
    T.tensor out_data = T.neg(x.data)
    int nid = register_op("neg", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    ag_tensor { data: out_data, grad T.zeros_like(out_data), graph_node_id nid, requires_grad x.requires_grad, is_leaf false, name: "neg" }
}

func ag_mse_loss(ag_tensor pred, ag_tensor target) ag_tensor {
    T.tensor loss_data = T.mse_loss(pred.data, target.data)
    int nid = register_op("mse_loss", [pred.graph_node_id, target.graph_node_id], loss_data,
                           pred.requires_grad || target.requires_grad, new float[0], new int[0])
    ag_tensor { data: loss_data, grad T.zeros_like(loss_data), graph_node_id nid, requires_grad true, is_leaf false, name: "mse_loss" }
}

func ag_cross_entropy(ag_tensor logits, int[] target_classes) ag_tensor {
    T.tensor probs = T.softmax(logits.data, logits.data.shape.ndim - 1)
    T.tensor log_probs = T.log_t(probs)
    int batch_size = logits.data.shape.dims[0]
    int num_classes = logits.data.shape.dims[logits.data.shape.ndim - 1]
    float loss_val = 0.0
    int i = 0
    for i < batch_size {
        int cls = target_classes[i]
        if cls >= 0 && cls < num_classes {
            float p = probs.data[i * num_classes + cls]
            if p > 1e-10 { loss_val = loss_val - M.log(p) }
            else { loss_val = loss_val + 50.0 }
        }
        i = i + 1
    }
    loss_val = loss_val / batch_size as float
    T.tensor loss_data = T.scalar(loss_val)
    int psz = T.numel(probs)
    float[] cache = new float[psz + batch_size]
    int j = 0
    for j < psz { cache[j] = probs.data[j]; j = j + 1 }
    j = 0
    for j < batch_size { cache[psz + j] = target_classes[j] as float; j = j + 1 }
    int nid = register_op("cross_entropy", [logits.graph_node_id], loss_data, true, cache, target_classes)
    ag_tensor { data: loss_data, grad T.scalar(0.0), graph_node_id nid, requires_grad true, is_leaf false, name: "ce_loss" }
}

func ag_l1_loss(ag_tensor pred, ag_tensor target) ag_tensor {
    T.tensor loss_data = T.l1_loss(pred.data, target.data)
    int nid = register_op("l1_loss", [pred.graph_node_id, target.graph_node_id], loss_data,
                           pred.requires_grad || target.requires_grad, new float[0], new int[0])
    ag_tensor { data: loss_data, grad T.zeros_like(loss_data), graph_node_id nid, requires_grad true, is_leaf false, name: "l1_loss" }
}

func ag_bce_logits(ag_tensor logits, ag_tensor targets) ag_tensor {
    T.tensor loss_data = T.bce_logits_loss(logits.data, targets.data)
    int nid = register_op("bce_logits", [logits.graph_node_id, targets.graph_node_id], loss_data,
                           logits.requires_grad || targets.requires_grad, new float[0], new int[0])
    ag_tensor { data: loss_data, grad T.zeros_like(loss_data), graph_node_id nid, requires_grad true, is_leaf false, name: "bce_logits" }
}

func backward(ag_tensor loss_tensor) Map<string, T.tensor> {
    int loss_nid = loss_tensor.graph_node_id
    if loss_nid >= 0 && loss_nid < _global_graph.node_count {
        _global_graph.nodes[loss_nid].grad = T.ones_like(loss_tensor.data)
    }
    int[] topo = topological_sort()
    int idx = len(topo) - 1
    for idx >= 0 {
        int nid = topo[idx]
        if nid >= 0 && nid < _global_graph.node_count {
            graph_node node = _global_graph.nodes[nid]
            if !node.is_leaf && node.requires_grad && T.numel(node.grad) > 0 {
                compute_backward(node)
            }
        }
        idx = idx - 1
    }
    collect_leaf_gradients()
}

func compute_backward(graph_node node) void {
    T.tensor grad_out = node.grad
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
        accumulate_grad(node.input_node_ids[1], T.neg(grad_out))
    }
    else if op == "mul" {
        T.tensor inp0_data = get_output(node.input_node_ids[0])
        T.tensor inp1_data = get_output(node.input_node_ids[1])
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, inp1_data))
        accumulate_grad(node.input_node_ids[1], T.mul(grad_out, inp0_data))
    }
    else if op == "mul_scalar" {
        float s = node.cache_float[0]
        accumulate_grad(node.input_node_ids[0], T.mul_scalar(grad_out, s))
    }
    else if op == "div" {
        T.tensor inp0_data = get_output(node.input_node_ids[0])
        T.tensor inp1_data = get_output(node.input_node_ids[1])
        accumulate_grad(node.input_node_ids[0], T.div(grad_out, inp1_data))
        T.tensor sq_inp1 = T.square(inp1_data)
        T.tensor neg_prod = T.neg(T.mul(grad_out, inp0_data))
        accumulate_grad(node.input_node_ids[1], T.div(neg_prod, sq_inp1))
    }
    else if op == "matmul" {
        T.tensor a = get_output(node.input_node_ids[0])
        T.tensor b = get_output(node.input_node_ids[1])
        T.tensor b_t = T.transpose_2d(b)
        T.tensor a_t = T.transpose_2d(a)
        accumulate_grad(node.input_node_ids[0], T.matmul(grad_out, b_t))
        accumulate_grad(node.input_node_ids[1], T.matmul(a_t, grad_out))
    }
    else if op == "relu" {
        T.tensor inp = get_output(node.input_node_ids[0])
        int n = T.numel(inp)
        float[] mask_v = new float[n]
        int i = 0
        for i < n {
            if inp.data[i] > 0 { mask_v[i] = 1.0 }
            else { mask_v[i] = 0.0 }
            i = i + 1
        }
        T.tensor mask = T.make_tensor(mask_v, inp.shape.dims)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, mask))
    }
    else if op == "gelu" {
        T.tensor inp = get_output(node.input_node_ids[0])
        int n = T.numel(inp)
        float[] gv = new float[n]
        float SQRT_2_PI = 0.7978845608028654
        int i = 0
        for i < n {
            float x = inp.data[i]
            float inner = SQRT_2_PI * (x + 0.044715 * x * x * x)
            float ei = M.exp(2.0 * inner)
            float th = (ei - 1.0) / (ei + 1.0)
            gv[i] = 0.5 * (1.0 + th)
            i = i + 1
        }
        T.tensor g = T.make_tensor(gv, inp.shape.dims)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, g))
    }
    else if op == "softmax" {
        int dim = node.cache_int[len(node.cache_int) - 1]
        T.tensor probs = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, probs))
    }
    else if op == "cross_entropy" {
        int batch_size = get_output(node.input_node_ids[0]).shape.dims[0]
        int num_classes = get_output(node.input_node_ids[0]).shape.dims[get_output(node.input_node_ids[0]).shape.ndim - 1]
        int psz = batch_size * num_classes
        T.tensor grad_input = T.zeros(get_output(node.input_node_ids[0]).shape.dims)
        int i = 0
        for i < batch_size {
            int cls = node.cache_int[i]
            int offset = i * num_classes
            int j = 0
            for j < num_classes {
                float p = node.cache_float[offset + j]
                if j == cls { grad_input.data[offset + j] = (p - 1.0) / batch_size as float }
                else { grad_input.data[offset + j] = p / batch_size as float }
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
        T.tensor scaled = T.div_scalar(grad_out, dsize as float)
        T.tensor expanded = broadcast_to(scaled, get_output(node.input_node_ids[0]).shape.dims)
        accumulate_grad(node.input_node_ids[0], expanded)
    }
    else if op == "sum" {
        T.tensor expanded = broadcast_to(grad_out, get_output(node.input_node_ids[0]).shape.dims)
        accumulate_grad(node.input_node_ids[0], expanded)
    }
    else if op == "view" {
        int[] orig_shape = cache_to_ints(node.cache_int, 1, len(node.output_data.shape.dims))
        T.tensor reshaped = T.reshape(grad_out, orig_shape)
        accumulate_grad(node.input_node_ids[0], reshaped)
    }
    else if op == "transpose" {
        int d0 = node.cache_int[0]
        int d1 = node.cache_int[1]
        T.tensor reverted = T.transpose(grad_out, d0, d1)
        accumulate_grad(node.input_node_ids[0], reverted)
    }
    else if op == "square" {
        T.tensor inp = get_output(node.input_node_ids[0])
        T.tensor two_x = T.mul_scalar(inp, 2.0)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, two_x))
    }
    else if op == "neg" {
        accumulate_grad(node.input_node_ids[0], T.neg(grad_out))
    }
    else if op == "sigmoid" {
        T.tensor sig = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        T.tensor one_minus_sig = T.sub(T.ones_like(sig), sig)
        T.tensor dsig = T.mul(sig, one_minus_sig)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, dsig))
    }
    else if op == "tanh" {
        T.tensor th = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        T.tensor sq = T.square(th)
        T.tensor dth = T.sub(T.ones_like(th), sq)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, dth))
    }
    else if op == "layer_norm" {
        accumulate_grad(node.input_node_ids[0], grad_out)
    }
    else if op == "mse_loss" {
        T.tensor pred = get_output(node.input_node_ids[0])
        T.tensor target = get_output(node.input_node_ids[1])
        int n = T.numel(pred)
        T.tensor diff = T.sub(pred, target)
        T.tensor grad_p = T.mul_scalar(diff, 2.0 / n as float)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, grad_p))
        T.tensor grad_t = T.mul_scalar(T.neg(diff), 2.0 / n as float)
        accumulate_grad(node.input_node_ids[1], T.mul(grad_out, grad_t))
    }
    else if op == "l1_loss" {
        T.tensor pred = get_output(node.input_node_ids[0])
        T.tensor target = get_output(node.input_node_ids[1])
        int n = T.numel(pred)
        T.tensor diff = T.sub(pred, target)
        T.tensor sign_diff = elemwise_sign(diff)
        T.tensor grad_p = T.div_scalar(sign_diff, n as float)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, grad_p))
    }
    else if op == "bce_logits" {
        T.tensor sig = T.sigmoid(get_output(node.input_node_ids[0]))
        T.tensor target = get_output(node.input_node_ids[1])
        int n = T.numel(sig)
        T.tensor diff = T.sub(sig, target)
        T.tensor grad_p = T.div_scalar(diff, n as float)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, grad_p))
    }

func accumulate_grad(int target_nid, T.tensor grad_delta) void {
    if target_nid >= 0 && target_nid < _global_graph.node_count {
        T.tensor current = _global_graph.nodes[target_nid].grad
        int n = T.numel(current)
        int i = 0
        for i < n {
            current.data[i] = current.data[i] + grad_delta.data[i]
            i = i + 1
        }
        _global_graph.nodes[target_nid].grad = current
    }
}

func collect_leaf_gradients() Map[string, T.tensor> {
    Map<string, T.tensor> result = new_map()
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

func get_output(int nid) T.tensor {
    if nid >= 0 && nid < _global_graph.node_count {
        return _global_graph.nodes[nid].output_data
    }
    T.zeros({0})
}

func make_cache_tensor(float[] cache, int[] shape) T.tensor {
    T.tensor t = T.make_tensor(cache, shape)
    t
}

func broadcast_to(T.tensor grad, int[] orig_shape) T.tensor {
    T.tensor r = T.reshape(grad, orig_shape)
    r
}

func elemwise_sign(T.tensor t) T.tensor {
    int n = T.numel(t)
    float[] v = new float[n]
    int i = 0
    for i < n {
        if t.data[i] > 0 { v[i] = 1.0 }
        else if t.data[i] < 0 { v[i] = -1.0 }
        else { v[i] = 0.0 }
        i = i + 1
    }
    T.tensor { shape: t.shape, data v, device: "cpu", requires_grad false }
}

func register_op(string op_name, int[] input_ids, T.tensor output, bool req_grad,
                  float[] cache_f, int[] cache_i) int {
    graph_node n
    n.op_name = op_name
    n.input_node_ids = input_ids
    n.output_data = output
    n.cache_float = cache_f
    n.cache_int = cache_i
    n.is_leaf = false
    n.requires_grad = req_grad
    n.grad = T.zeros_like(output)
    add_node(_global_graph, n)
}

func cache_to_ints(int[] arr, int start, int count) int[] {
    int[] result = new int[count]
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
    Map<string, T.tensor> velocity
    Map<string, T.tensor> second_moment
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

func zero_grad(Map<string, ag_tensor> params) void {
    for name, param in params {
        param.grad = T.zeros_like(param.data)
    }
}

func sgd_step(optimizer opt, Map<string, ag_tensor> params) void {
    opt.step = opt.step + 1
    for name, param in params {
        if !param.requires_grad { continue }
        T.tensor g = param.grad
        if opt.weight_decay > 0 {
            g = T.add(g, T.mul_scalar(param.data, opt.weight_decay))
        }
        if opt.momentum > 0 {
            if !(name in opt.velocity) {
                map_put(opt.velocity, name, T.zeros_like(param.data))
            }
            T.tensor v = opt.velocity[name]
            v = T.add(T.mul_scalar(v, opt.momentum), g)
            map_put(opt.velocity, name, v)
            param.data = T.sub(param.data, T.mul_scalar(v, opt.lr))
        } else {
            param.data = T.sub(param.data, T.mul_scalar(g, opt.lr))
        }
    }
}

func adam_step(optimizer opt, Map<string, ag_tensor> params) void {
    int t = opt.step + 1
    opt.step = t
    float bias1 = 1.0 - M.pow(opt.momentum, t as float)
    float bias2 = 1.0 - M.pow(opt.beta2, t as float)
    for name, param in params {
        if !param.requires_grad { continue }
        T.tensor g = param.grad
        if !(name in opt.velocity) {
            map_put(opt.velocity, name, T.zeros_like(param.data))
            map_put(opt.second_moment, name, T.zeros_like(param.data))
        }
        T.tensor m = opt.velocity[name]
        T.tensor v = opt.second_moment[name]
        m = T.add(T.mul_scalar(m, opt.momentum), T.mul_scalar(g, 1.0 - opt.momentum))
        map_put(opt.velocity, name, m)
        v = T.add(T.mul_scalar(v, opt.beta2), T.mul_scalar(T.square(g), 1.0 - opt.beta2))
        map_put(opt.second_moment, name, v)
        T.tensor m_hat = T.div(m, scalar(bias1))
        T.tensor v_hat = T.div(v, scalar(bias2))
        if opt.weight_decay > 0 {
            param.data = T.sub(param.data, T.mul_scalar(param.data, opt.lr * opt.weight_decay))
        }
        T.tensor sqrt_v = T.sqrt_t(v_hat)
        T.tensor denom = T.add(sqrt_v, scalar(opt.eps))
        T.tensor update = T.div(m_hat, denom)
        param.data = T.sub(param.data, T.mul_scalar(update, opt.lr))
    }
}

func clip_grad_norm_(Map<string, ag_tensor> params, float max_norm) float {
    float total_sq = 0.0
    for name, param in params {
        total_sq = total_sq + item(T.norm(param.grad))
    }
    float total_norm = sqrt(total_sq)
    if total_norm > max_norm {
        float scale = max_norm / (total_norm + 1e-6)
        for name, param in params {
            param.grad = T.mul_scalar(param.grad, scale)
        }
    }
    total_norm
}

func clip_grad_value_(Map<string, ag_tensor> params, float clip_val) void {
    for name, param in params {
        param.grad = T.clamp_t(param.grad, -clip_val, clip_val)
    }
}

func lr_step(optimizer opt, int epoch) void {
    if epoch > 0 && mod(epoch, 30) == 0 {
        opt.lr = opt.lr * 0.1
    }
}
