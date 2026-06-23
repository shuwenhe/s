// ============================================
// S Language Autograd - Automatic Differentiation
// 自动微分框架 - 深度学习训练核心
// ============================================
//
// 提供完整的反向模式自动微分能力：
// - 计算图构建与追踪
// - 反向传播 (Backpropagation)
// - 梯度计算与累积
// - 优化器集成接口
//
// 设计原则:
// 1. 与 tensor_core.s 的 Tensor 类型无缝对接
// 2. 支持所有常用神经网络操作的梯度
// 3. 内存高效: 按需缓存前向值
// 4. 可扩展: 新操作只需实现 forward + backward
// ============================================
package std.autograd

use std.tensor_core as T
use std.math_dl as M

// ============================================
// Core Data Structures (核心数据结构)
// ============================================

// 计算图节点 - 记录一次运算的所有信息
struct GraphNode {
    int id                    // 节点唯一ID
    string op_name            // 操作名称 "add", "mul", "matmul", ...
    int[] input_node_ids      // 输入节点的ID列表
    int output_node_id        // 输出节点ID (-1表示是叶子/输出)
    
    // 前向传播的输出数据
    T.Tensor output_data
    
    // 反向传播需要的缓存的中间值
    float[] cache_float       // 浮点缓存 (如 softmax 的 e^x)
    int[] cache_int           // 整数缓存 (如目标类别)
    
    // 是否为叶子节点 (参数/输入)
    bool is_leaf
    
    // 该节点是否需要梯度
    bool requires_grad
    
    // 累积的梯度 (与output_data同形状)
    T.Tensor grad
}

// Autograd张量 - 包装普通Tensor + 梯度信息
struct AGTensor {
    T.Tensor data             // 实际数据
    T.Tensor grad             // 梯度 (初始为零)
    int graph_node_id         // 在计算图中的节点ID
    bool requires_grad        // 是否需要计算梯度
    bool is_leaf              // 是否为叶子(可训练参数)
    string name               // 名称 (用于调试和参数管理)
}

// 计算图 - 管理所有节点和拓扑排序
struct ComputationGraph {
    GraphNode[] nodes          // 所有节点
    int node_count            // 当前节点数
    int[] topo_order          // 拓扑排序结果
}

// ============================================
// Graph Management (计算图管理)
// ============================================

var _global_graph = ComputationGraph { nodes: new GraphNode[2000], node_count: 0 }
var _next_node_id = 0

// 创建新计算图
func new_graph() ComputationGraph {
    _next_node_id = 0
    ComputationGraph { nodes: new GraphNode[2000], node_count: 0 }
}

// 向图中添加节点，返回节点ID
func add_node(ComputationGraph mut g, GraphNode n) int {
    if g.node_count < 2000 {
        n.id = _next_node_id
        g.nodes[g.node_count] = n
        g.node_count = g.node_count + 1
        _next_node_id = _next_node_id + 1
        return n.id
    }
    -1  // 图已满
}

// 获取指定ID的节点
func get_node(ComputationGraph g, int id) GraphNode {
    int i = 0
    while i < g.node_count {
        if g.nodes[i].id == id { return g.nodes[i] }
        i = i + 1
    }
    GraphNode {}  // 未找到返回空
}

// ============================================
// Topological Sort (拓扑排序)
// 用于确定反向传播的正确顺序
// ============================================

// DFS标记访问状态
func _dfs_topo(int node_idx, bool[] visited, int[] order, int mut order_pos) void {
    if visited[node_idx] { return }
    visited[node_idx] = true
    
    GraphNode n = get_node(_global_graph, node_idx)  // 需要全局访问
    int i = 0
    while i < len(n.input_node_ids) {
        _dfs_topo(n.input_node_ids[i], visited, order, order_pos)
        i = i + 1
    }
    
    order[order_pos] = node_idx
    order_pos = order_pos + 1
}

// 对整个图进行拓扑排序
func topological_sort() int[] {
    bool[] visited = new bool[_global_graph.node_count]
    int[] order = new int[_global_graph.node_count]
    int pos = 0
    
    int i = 0
    while i < _global_graph.node_count {
        if !visited[i] {
            _dfs_topo(_global_graph.nodes[i].id, visited, order, pos)
        }
        i = i + 1
    }
    
    order
}

// ============================================
// AGTensor Creation & Utilities
// ============================================

// 从普通Tensor创建AGTensor（不需要梯度）
func from_tensor(T.Tensor data) AGTensor {
    AGTensor {
        data: data,
        grad: T.zeros_like(data),
        graph_node_id: -1,
        requires_grad: false,
        is_leaf: false,
        name: ""
    }
}

// 创建叶子节点（模型参数）
func parameter(T.Tensor data, string name) AGTensor {
    int nid = add_leaf_node(data, name)
    AGTensor {
        data: data,
        grad: T.zeros_like(data),
        graph_node_id: nid,
        requires_grad: true,
        is_leaf: true,
        name: name
    }
}

// 添加叶子节点到计算图
func add_leaf_node(T.Tensor data, string name) int {
    GraphNode n
    n.op_name = "leaf"
    n.input_node_ids = new int[0]
    n.output_data = data
    n.is_leaf = true
    n.requires_grad = true
    n.grad = T.zeros_like(data)
    n.name = name
    add_node(_global_graph, n)
}

// 断开计算图（停止梯度）
func detach(AGTensor t) AGTensor {
    AGTensor {
        data: t.data,
        grad: T.zeros_like(t.data),
        graph_node_id: -1,
        requires_grad: false,
        is_leaf: true,
        name: t.name + "_detached"
    }
}

// 获取标量值
func item(AGTensor t) float { T.item(t.data) }

// 获取参数总数
func num_params(AGTensor t) int { T.numel(t.data) }

// 打印信息
func ag_info(AGTensor t) void {
    println("AGTensor(name=" + t.name + ", shape=" + T.shape_str(t.shape) + 
            ", req_grad=" + string(t.requires_grad) + ", leaf=" + string(t.is_leaf) + ")")
}

// ============================================
// Forward Operations with Autograd Tracking
// 每个函数同时完成:
//   1. 前向计算
//   2. 注册到计算图
//   3. 返回带梯度信息的AGTensor
// ============================================

// 加法: c = a + b
// ∂c/∂a = 1, ∂c/∂b = 1 (逐元素)
func ag_add(AGTensor a, AGTensor b) AGTensor {
    T.Tensor out_data = T.add(a.data, b.data)
    bool req_grad = a.requires_grad || b.requires_grad
    
    // 注册计算图节点
    int nid = register_op("add", [a.graph_node_id, b.graph_node_id], out_data, 
                           req_grad, new float[0], new int[0])
    
    AGTensor {
        data: out_data,
        grad: T.zeros_like(out_data),
        graph_node_id: nid,
        requires_grad: req_grad,
        is_leaf: false,
        name: "add"
    }
}

// 标量加法
func ag_add_scalar(AGTensor a, float s) AGTensor {
    T.Tensor out_data = T.add_scalar(a.data, s)
    int nid = register_op("add_scalar", [a.graph_node_id], out_data, 
                           a.requires_grad, [s], new int[0])
    AGTensor {
        data: out_data, grad: T.zeros_like(out_data),
        graph_node_id: nid, requires_grad: a.requires_grad,
        is_leaf: false, name: "add_s"
    }
}

// 减法: c = a - b
// ∂c/∂a = 1, ∂c/∂b = -1
func ag_sub(AGTensor a, AGTensor b) AGTensor {
    T.Tensor out_data = T.sub(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("sub", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: rg, is_leaf: false, name: "sub" }
}

// 乘法: c = a * b (逐元素)
// ∂c/∂a = b, ∂c/∂b = a
func ag_mul(AGTensor a, AGTensor b) AGTensor {
    T.Tensor out_data = T.mul(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("mul", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: rg, is_leaf: false, name: "mul" }
}

// 标量乘法
func ag_mul_scalar(AGTensor a, float s) AGTensor {
    T.Tensor out_data = T.mul_scalar(a.data, s)
    int nid = register_op("mul_scalar", [a.graph_node_id], out_data, a.requires_grad, [s], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: a.requires_grad, is_leaf: false, name: "mul_s" }
}

// 除法: c = a / b
// ∂c/∂a = 1/b, ∂c/∂b = -a/b²
func ag_div(AGTensor a, AGTensor b) AGTensor {
    T.Tensor out_data = T.div(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("div", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: rg, is_leaf: false, name: "div" }
}

// 矩阵乘法: C = A @ B
// ∂C/∂A = grad @ B^T,  ∂C/∂B = A^T @ grad
func ag_matmul(AGTensor a, AGTensor b) AGTensor {
    T.Tensor out_data = T.matmul(a.data, b.data)
    bool rg = a.requires_grad || b.requires_grad
    int nid = register_op("matmul", [a.graph_node_id, b.graph_node_id], out_data, rg, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: rg, is_leaf: false, name: "matmul" }
}

// ReLU: y = max(0, x)
// dy/dx = 1 if x>0 else 0
func ag_relu(AGTensor x) AGTensor {
    T.Tensor out_data = T.relu(x.data)
    int nid = register_op("relu", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "relu" }
}

// GELU
func ag_gelu(AGTensor x) AGTensor {
    T.Tensor out_data = T.gelu(x.data)
    int nid = register_op("gelu", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "gelu" }
}

// Softmax (沿dim维度)
func ag_softmax(AGTensor x, int dim) AGTensor {
    T.Tensor out_data = T.softmax(x.data, dim)
    // 缓存softmax结果用于backward
    int sz = T.numel(out_data)
    float[] cache = new float[sz]
    int i = 0
    while i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    
    int nid = register_op("softmax", [x.graph_node_id], out_data, x.requires_grad, cache, [dim])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "softmax" }
}

// Layer Normalization
func ag_layer_norm(AGTensor x, float eps) AGTensor {
    T.Tensor out_data = T.layer_norm(x.data, eps)
    int nid = register_op("layer_norm", [x.graph_node_id], out_data, x.requires_grad, [eps], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "layernorm" }
}

// Sigmoid
func ag_sigmoid(AGTensor x) AGTensor {
    T.Tensor out_data = T.sigmoid(x.data)
    int sz = T.numel(out_data)
    float[] cache = new float[sz]
    int i = 0
    while i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("sigmoid", [x.graph_node_id], out_data, x.requires_grad, cache, new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "sigmoid" }
}

// Tanh
func ag_tanh(AGTensor x) AGTensor {
    T.Tensor out_data = T.tanh_t(x.data)
    int sz = T.numel(out_data)
    float[] cache = new float[sz]
    int i = 0
    while i < sz { cache[i] = out_data.data[i]; i = i + 1 }
    int nid = register_op("tanh", [x.graph_node_id], out_data, x.requires_grad, cache, new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "tanh" }
}

// Mean along dimension
func ag_mean(AGTensor x, int dim, bool keepdim) AGTensor {
    T.Tensor out_data = T.mean_dim(x.data, dim, keepdim)
    int nid = register_op("mean", [x.graph_node_id], out_data, x.requires_grad, new float[0], [dim, keepdim ? 1 : 0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "mean" }
}

// Sum along dimension
func ag_sum(AGTensor x, int dim, bool keepdim) AGTensor {
    T.Tensor out_data = T.sum_dim(x.data, dim, keepdim)
    int nid = register_op("sum", [x.graph_node_id], out_data, x.requires_grad, new float[0], [dim, keepdim ? 1 : 0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "sum" }
}

// Reshape / View
func ag_view(AGTensor x, int[] shape) AGTensor {
    T.Tensor out_data = T.reshape(x.data, shape)
    int nid = register_op("view", [x.graph_node_id], out_data, x.requires_grad, new float[0], shape)
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "view" }
}

// Transpose
func ag_transpose(AGTensor x, int d0, int d1) AGTensor {
    T.Tensor out_data = T.transpose(x.data, d0, d1)
    int nid = register_op("transpose", [x.graph_node_id], out_data, x.requires_grad, new float[0], [d0, d1])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "transpose" }
}

// Square
func ag_square(AGTensor x) AGTensor {
    T.Tensor out_data = T.square(x.data)
    int nid = register_op("square", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "square" }
}

// Negation
func ag_neg(AGTensor x) AGTensor {
    T.Tensor out_data = T.neg(x.data)
    int nid = register_op("neg", [x.graph_node_id], out_data, x.requires_grad, new float[0], new int[0])
    AGTensor { data: out_data, grad: T.zeros_like(out_data), graph_node_id: nid, requires_grad: x.requires_grad, is_leaf: false, name: "neg" }
}

// ============================================
// Loss Functions (损失函数 - 带Autograd)
// ============================================

// MSE Loss
func ag_mse_loss(AGTensor pred, AGTensor target) AGTensor {
    T.Tensor loss_data = T.mse_loss(pred.data, target.data)
    int nid = register_op("mse_loss", [pred.graph_node_id, target.graph_node_id], loss_data, 
                           pred.requires_grad || target.requires_grad, new float[0], new int[0])
    AGTensor { data: loss_data, grad: T.zeros_like(loss_data), graph_node_id: nid, requires_grad: true, is_leaf: false, name: "mse_loss" }
}

// Cross Entropy Loss (输入logits, 目标one-hot或class indices)
// 内部包含 softmax + log + mean
func ag_cross_entropy(AGTensor logits, int[] target_classes) AGTensor {
    // 前向: softmax -> log -> gather targets -> neg mean
    T.Tensor probs = T.softmax(logits.data, logits.data.shape.ndim - 1)
    T.Tensor log_probs = T.log_t(probs)
    
    int batch_size = logits.data.shape.dims[0]
    int num_classes = logits.data.shape.dims[logits.data.shape.ndim - 1]
    float loss_val = 0.0
    
    int i = 0
    while i < batch_size {
        int cls = target_classes[i]
        if cls >= 0 && cls < num_classes {
            float p = probs.data[i * num_classes + cls]
            if p > 1e-10 { loss_val = loss_val - M.log(p) }
            else { loss_val = loss_val + 50.0 }  // 大惩罚
        }
        i = i + 1
    }
    loss_val = loss_val / batch_size as float
    
    T.Tensor loss_data = T.scalar(loss_val)
    // 缓存probs和targets用于backward
    int psz = T.numel(probs)
    float[] cache = new float[psz + batch_size]
    int j = 0
    while j < psz { cache[j] = probs.data[j]; j = j + 1 }
    j = 0
    while j < batch_size { cache[psz + j] = target_classes[j] as float; j = j + 1 }
    
    int nid = register_op("cross_entropy", [logits.graph_node_id], loss_data, true, cache, target_classes)
    AGTensor { data: loss_data, grad: T.scalar(0.0), graph_node_id: nid, requires_grad: true, is_leaf: false, name: "ce_loss" }
}

// L1 Loss
func ag_l1_loss(AGTensor pred, AGTensor target) AGTensor {
    T.Tensor loss_data = T.l1_loss(pred.data, target.data)
    int nid = register_op("l1_loss", [pred.graph_node_id, target.graph_node_id], loss_data, 
                           pred.requires_grad || target.requires_grad, new float[0], new int[0])
    AGTensor { data: loss_data, grad: T.zeros_like(loss_data), graph_node_id: nid, requires_grad: true, is_leaf: false, name: "l1_loss" }
}

// Binary Cross Entropy with Logits
func ag_bce_logits(AGTensor logits, AGTensor targets) AGTensor {
    T.Tensor loss_data = T.bce_logits_loss(logits.data, targets.data)
    int nid = register_op("bce_logits", [logits.graph_node_id, targets.graph_node_id], loss_data, 
                           logits.requires_grad || targets.requires_grad, new float[0], new int[0])
    AGTensor { data: loss_data, grad: T.zeros_like(loss_data), graph_node_id: nid, requires_grad: true, is_leaf: false, name: "bce_logits" }
}

// ============================================
// Backward Pass (反向传播核心)
// ============================================

// 从损失张量执行完整反向传播
// 返回一个映射: 叶子节点名称 -> 梯度Tensor
// 
// 算法流程:
// 1. 将loss的梯度设为1.0 (dL/dL = 1)
// 2. 对计算图做拓扑排序
// 3. 按逆序遍历每个节点
// 4. 对每个节点调用其对应的backward函数
// 5. 将计算的梯度累加到输入节点的grad字段
// ============================================

// 执行反向传播
func backward(AGTensor loss_tensor) Map<string, T.Tensor> {
    // Step 1: 初始化 loss 梯度为 1
    int loss_nid = loss_tensor.graph_node_id
    if loss_nid >= 0 && loss_nid < _global_graph.node_count {
        _global_graph.nodes[loss_nid].grad = T.ones_like(loss_tensor.data)
    }
    
    // Step 2: 拓扑排序
    int[] topo = topological_sort()
    
    // Step 3-5: 逆序遍历并计算梯度
    int idx = len(topo) - 1
    while idx >= 0 {
        int nid = topo[idx]
        
        if nid >= 0 && nid < _global_graph.node_count {
            GraphNode node = _global_graph.nodes[nid]
            
            // 只处理需要梯度的非叶子节点
            if !node.is_leaf && node.requires_grad && T.numel(node.grad) > 0 {
                // 计算该操作的梯度
                compute_backward(node)
            }
        }
        
        idx = idx - 1
    }
    
    // 收集所有叶子节点的梯度
    collect_leaf_gradients()
}

// 根据操作类型分发梯度计算
func compute_backward(GraphNode node) void {
    T.Tensor grad_out = node.grad
    string op = node.op_name
    
    if op == "add" {
        // ∂(a+b)/∂a = grad, ∂(a+b)/∂b = grad
        accumulate_grad(node.input_node_ids[0], grad_out)
        accumulate_grad(node.input_node_ids[1], grad_out)
    }
    else if op == "add_scalar" {
        accumulate_grad(node.input_node_ids[0], grad_out)
    }
    else if op == "sub" {
        // ∂(a-b)/∂a = grad, ∂(a-b)/∂b = -grad
        accumulate_grad(node.input_node_ids[0], grad_out)
        accumulate_grad(node.input_node_ids[1], T.neg(grad_out))
    }
    else if op == "mul" {
        // ∂(a*b)/∂a = grad*b, ∂(a*b)/∂b = grad*a
        T.Tensor inp0_data = get_output(node.input_node_ids[0])
        T.Tensor inp1_data = get_output(node.input_node_ids[1])
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, inp1_data))
        accumulate_grad(node.input_node_ids[1], T.mul(grad_out, inp0_data))
    }
    else if op == "mul_scalar" {
        float s = node.cache_float[0]
        accumulate_grad(node.input_node_ids[0], T.mul_scalar(grad_out, s))
    }
    else if op == "div" {
        T.Tensor inp0_data = get_output(node.input_node_ids[0])
        T.Tensor inp1_data = get_output(node.input_node_ids[1])
        // ∂(a/b)/∂a = grad/b, ∂(a/b)/∂b = -grad*a/b²
        accumulate_grad(node.input_node_ids[0], T.div(grad_out, inp1_data))
        T.Tensor sq_inp1 = T.square(inp1_data)
        T.Tensor neg_prod = T.neg(T.mul(grad_out, inp0_data))
        accumulate_grad(node.input_node_ids[1], T.div(neg_prod, sq_inp1))
    }
    else if op == "matmul" {
        T.Tensor a = get_output(node.input_node_ids[0])
        T.Tensor b = get_output(node.input_node_ids[1])
        // ∂C/∂A = grad @ B^T, ∂C/∂B = A^T @ grad
        T.Tensor b_t = T.transpose_2d(b)
        T.Tensor a_t = T.transpose_2d(a)
        accumulate_grad(node.input_node_ids[0], T.matmul(grad_out, b_t))
        accumulate_grad(node.input_node_ids[1], T.matmul(a_t, grad_out))
    }
    else if op == "relu" {
        // dReLU/dx = 1 if x>0 else 0
        T.Tensor inp = get_output(node.input_node_ids[0])
        int n = T.numel(inp)
        float[] mask_v = new float[n]
        int i = 0
        while i < n {
            if inp.data[i] > 0 { mask_v[i] = 1.0 }
            else { mask_v[i] = 0.0 }
            i = i + 1
        }
        T.Tensor mask = T.make_tensor(mask_v, inp.shape.dims)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, mask))
    }
    else if op == "gelu" {
        // 近似GELU的导数比较复杂，这里简化处理
        // dGELU/dx ≈ 0.5 * (1 + tanh'(inner)) * (...) + gelu * 0
        // 使用数值近似: 直接用 sigmoid 近似
        T.Tensor inp = get_output(node.input_node_ids[0])
        int n = T.numel(inp)
        float[] gv = new float[n]
        float SQRT_2_PI = 0.7978845608028654
        int i = 0
        while i < n {
            float x = inp.data[i]
            float inner = SQRT_2_PI * (x + 0.044715 * x * x * x)
            float ei = M.exp(2.0 * inner)
            float th = (ei - 1.0) / (ei + 1.0)
            // dGELU ≈ 0.5*(1+tanh) + 0.5*x*sech²(inner)*derivative(inner)
            gv[i] = 0.5 * (1.0 + th)  // 简化版
            i = i + 1
        }
        T.Tensor g = T.make_tensor(gv, inp.shape.dims)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, g))
    }
    else if op == "softmax" {
        // dSoftmax/dx_i = p_i * (δ_ij - p_j) 其中p=softmax(x)
        // 即 grad_out * p - p * sum(grad_out * p)
        int dim = node.cache_int[len(node.cache_int) - 1]
        T.Tensor probs = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        // 简化: 对于交叉熵损失的softmax+log组合，梯度就是 (probs - one_hot)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, probs))
    }
    else if op == "cross_entropy" {
        // dCE/dlogits = (probs - one_hot(targets)) / batch_size
        int batch_size = get_output(node.input_node_ids[0]).shape.dims[0]
        int num_classes = get_output(node.input_node_ids[0]).shape.dims[get_output(node.input_node_ids[0]).shape.ndim - 1]
        int psz = batch_size * num_classes
        
        T.Tensor grad_input = T.zeros(get_output(node.input_node_ids[0]).shape.dims)
        int i = 0
        while i < batch_size {
            int cls = node.cache_int[i]
            int offset = i * num_classes
            int j = 0
            while j < num_classes {
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
        // broadcast grad back and divide by dim size
        T.Tensor scaled = T.div_scalar(grad_out, dsize as float)
        T.Tensor expanded = broadcast_to(scaled, get_output(node.input_node_ids[0]).shape.dims)
        accumulate_grad(node.input_node_ids[0], expanded)
    }
    else if op == "sum" {
        T.Tensor expanded = broadcast_to(grad_out, get_output(node.input_node_ids[0]).shape.dims)
        accumulate_grad(node.input_node_ids[0], expanded)
    }
    else if op == "view" {
        // reshape gradient back to original shape
        int[] orig_shape = cache_to_ints(node.cache_int, 1, len(node.output_data.shape.dims))
        T.Tensor reshaped = T.reshape(grad_out, orig_shape)
        accumulate_grad(node.input_node_ids[0], reshaped)
    }
    else if op == "transpose" {
        int d0 = node.cache_int[0]
        int d1 = node.cache_int[1]
        // transpose again to revert
        T.Tensor reverted = T.transpose(grad_out, d0, d1)
        accumulate_grad(node.input_node_ids[0], reverted)
    }
    else if op == "square" {
        // d(x²)/dx = 2x
        T.Tensor inp = get_output(node.input_node_ids[0])
        T.Tensor two_x = T.mul_scalar(inp, 2.0)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, two_x))
    }
    else if op == "neg" {
        // d(-x)/dx = -1
        accumulate_grad(node.input_node_ids[0], T.neg(grad_out))
    }
    else if op == "sigmoid" {
        // dσ/dx = σ(1-σ)
        T.Tensor sig = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        T.Tensor one_minus_sig = T.sub(T.ones_like(sig), sig)
        T.Tensor dsig = T.mul(sig, one_minus_sig)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, dsig))
    }
    else if op == "tanh" {
        // dtanh/dx = 1 - tanh²
        T.Tensor th = make_cache_tensor(node.cache_float, node.output_data.shape.dims)
        T.Tensor sq = T.square(th)
        T.Tensor dth = T.sub(T.ones_like(th), sq)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, dth))
    }
    else if op == "layer_norm" {
        // 简化: 直接传递梯度
        accumulate_grad(node.input_node_ids[0], grad_out)
    }
    else if op == "mse_loss" {
        // dMSE/dpred = 2(pred-target)/n
        T.Tensor pred = get_output(node.input_node_ids[0])
        T.Tensor target = get_output(node.input_node_ids[1])
        int n = T.numel(pred)
        T.Tensor diff = T.sub(pred, target)
        T.Tensor grad_p = T.mul_scalar(diff, 2.0 / n as float)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, grad_p))
        T.Tensor grad_t = T.mul_scalar(T.neg(diff), 2.0 / n as float)
        accumulate_grad(node.input_node_ids[1], T.mul(grad_out, grad_t))
    }
    else if op == "l1_loss" {
        // dL1/dpred = sign(pred-target)/n
        T.Tensor pred = get_output(node.input_node_ids[0])
        T.Tensor target = get_output(node.input_node_ids[1])
        int n = T.numel(pred)
        T.Tensor diff = T.sub(pred, target)
        T.Tensor sign_diff = elemwise_sign(diff)
        T.Tensor grad_p = T.div_scalar(sign_diff, n as float)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, grad_p))
    }
    else if op == "bce_logits" {
        // dBCE/dlogits = σ(logits) - targets (Sigmoid + BCE 组合)
        T.Tensor sig = T.sigmoid(get_output(node.input_node_ids[0]))
        T.Tensor target = get_output(node.input_node_ids[1])
        int n = T.numel(sig)
        T.Tensor diff = T.sub(sig, target)
        T.Tensor grad_p = T.div_scalar(diff, n as float)
        accumulate_grad(node.input_node_ids[0], T.mul(grad_out, grad_p))
    }
    // 如果是叶子节点或不支持的op，不做任何事

// 累积梯度到指定节点
func accumulate_grad(int target_nid, T.Tensor grad_delta) void {
    if target_nid >= 0 && target_nid < _global_graph.node_count {
        T.Tensor current = _global_graph.nodes[target_nid].grad
        // 逐元素相加
        int n = T.numel(current)
        int i = 0
        while i < n {
            current.data[i] = current.data[i] + grad_delta.data[i]
            i = i + 1
        }
        _global_graph.nodes[target_nid].grad = current
    }
}

// 收集所有叶子(参数)节点的梯度
func collect_leaf_gradients() Map[string, T.Tensor> {
    Map<string, T.Tensor> result = new_map()
    
    int i = 0
    while i < _global_graph.node_count {
        GraphNode node = _global_graph.nodes[i]
        if node.is_leaf && node.requires_grad {
            map_put(result, node.name, node.grad)
        }
        i = i + 1
    }
    
    result
}

// 获取节点的输出数据
func get_output(int nid) T.Tensor {
    if nid >= 0 && nid < _global_graph.node_count {
        return _global_graph.nodes[nid].output_data
    }
    T.zeros({0})
}

// 从float缓存创建tensor
func make_cache_tensor(float[] cache, int[] shape) T.Tensor {
    T.Tensor t = T.make_tensor(cache, shape)
    t
}

// 广播梯度到原始形状 (简化版)
func broadcast_to(T.Tensor grad, int[] orig_shape) T.Tensor {
    T.Tensor r = T.reshape(grad, orig_shape)
    r
}

// 逐元素sign
func elemwise_sign(T.Tensor t) T.Tensor {
    int n = T.numel(t)
    float[] v = new float[n]
    int i = 0
    while i < n {
        if t.data[i] > 0 { v[i] = 1.0 }
        else if t.data[i] < 0 { v[i] = -1.0 }
        else { v[i] = 0.0 }
        i = i + 1
    }
    T.Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

// 注册操作到计算图的通用辅助函数
func register_op(string op_name, int[] input_ids, T.Tensor output, bool req_grad, 
                  float[] cache_f, int[] cache_i) int {
    GraphNode n
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

// 将int数组转为int列表 (用于cache解析)
func cache_to_ints(int[] arr, int start, int count) int[] {
    int[] result = new int[count]
    int i = 0
    while i < count { result[i] = arr[start + i]; i = i + 1 }
    result
}

// ============================================
// Optimizer Implementations (优化器实现)
// ============================================

struct Optimizer {
    string name              // "sgd" | "adam" | "adamw"
    float lr                 // 学习率 α
    float momentum           // β₁ (SGD动量 或 Adam一阶矩)
    float beta2              // β₂ (Adam二阶矩)
    float weight_decay       // 权重衰减 λ
    float eps                // 数值稳定常数 ε
    int step                 // 时间步 t
    
    // 每参数的状态
    Map<string, T.Tensor> velocity     // 动量 / 一阶矩 m
    Map<string, T.Tensor> second_moment // 二阶矩 v
}

// 创建SGD优化器
func make_sgd(float lr, float mom, float w_decay) Optimizer {
    Optimizer {
        name: "sgd",
        lr: lr,
        momentum: mom,
        weight_decay: w_decay,
        eps: 1e-8,
        step: 0
    }
}

// 创建Adam优化器
func make_adam(float lr, float b1, float b2, float w_decay, float eps) Optimizer {
    Optimizer {
        name: "adam",
        lr: lr,
        momentum: b1,     // beta1
        beta2: b2,
        weight_decay: w_decay,
        eps: eps,
        step: 0
    }
}

// 清零所有参数梯度
func zero_grad(Map<string, AGTensor> params) void {
    for name, param in params {
        param.grad = T.zeros_like(param.data)
    }
}

// SGD更新一步
func sgd_step(Optimizer mut opt, Map<string, AGTensor> params) void {
    opt.step = opt.step + 1
    
    for name, param in params {
        if !param.requires_grad { continue }
        
        T.Tensor g = param.grad
        
        // L2正则化 (权重衰减)
        if opt.weight_decay > 0 {
            g = T.add(g, T.mul_scalar(param.data, opt.weight_decay))
        }
        
        // 动量SGD
        if opt.momentum > 0 {
            if !(name in opt.velocity) {
                map_put(opt.velocity, name, T.zeros_like(param.data))
            }
            T.Tensor v = opt.velocity[name]
            // v = μ*v + g
            v = T.add(T.mul_scalar(v, opt.momentum), g)
            map_put(opt.velocity, name, v)
            // θ = θ - α*v
            param.data = T.sub(param.data, T.mul_scalar(v, opt.lr))
        } else {
            // Vanilla SGD: θ = θ - α*g
            param.data = T.sub(param.data, T.mul_scalar(g, opt.lr))
        }
    }
}

// Adam更新一步
func adam_step(Optimizer mut opt, Map<string, AGTensor> params) void {
    int t = opt.step + 1
    opt.step = t
    float bias1 = 1.0 - M.pow(opt.momentum, t as float)  // 1-β₁ᵗ
    float bias2 = 1.0 - M.pow(opt.beta2, t as float)      // 1-β₂ᵗ
    
    for name, param in params {
        if !param.requires_grad { continue }
        
        T.Tensor g = param.grad
        
        // 初始化矩估计
        if !(name in opt.velocity) {
            map_put(opt.velocity, name, T.zeros_like(param.data))
            map_put(opt.second_moment, name, T.zeros_like(param.data))
        }
        
        T.Tensor m = opt.velocity[name]      // 一阶矩
        T.Tensor v = opt.second_moment[name]  // 二阶矩
        
        // 更新一阶矩: m = β₁*m + (1-β₁)*g
        m = T.add(T.mul_scalar(m, opt.momentum), T.mul_scalar(g, 1.0 - opt.momentum))
        map_put(opt.velocity, name, m)
        
        // 更新二阶矩: v = β₂*v + (1-β₂)*g²
        v = T.add(T.mul_scalar(v, opt.beta2), T.mul_scalar(T.square(g), 1.0 - opt.beta2))
        map_put(opt.second_moment, name, v)
        
        // 偏差修正: m̂ = m/(1-β₁ᵗ), v̂ = v/(1-β₂ᵗ)
        T.Tensor m_hat = T.div(m, scalar(bias1))
        T.Tensor v_hat = T.div(v, scalar(bias2))
        
        // AdamW: 解耦权重衰减
        if opt.weight_decay > 0 {
            param.data = T.sub(param.data, T.mul_scalar(param.data, opt.lr * opt.weight_decay))
        }
        
        // 参数更新: θ = θ - α*m̂/(√v̂+ε)
        T.Tensor sqrt_v = T.sqrt_t(v_hat)
        T.Tensor denom = T.add(sqrt_v, scalar(opt.eps))
        T.Tensor update = T.div(m_hat, denom)
        param.data = T.sub(param.data, T.mul_scalar(update, opt.lr))
    }
}

// 梯度裁剪 - 按范数
// 返回实际裁剪后的总范数
func clip_grad_norm_(Map<string, AGTensor> params, float max_norm) float {
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

// 梯度裁剪 - 按值
func clip_grad_value_(Map<string, AGTensor> params, float clip_val) void {
    for name, param in params {
        param.grad = T.clamp_t(param.grad, -clip_val, clip_val)
    }
}

// 学习率调度: Step Decay
func lr_step(Optimizer mut opt, int epoch) void {
    if epoch > 0 && mod(epoch, 30) == 0 {
        opt.lr = opt.lr * 0.1
    }
}
