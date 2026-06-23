// ============================================
// S Language Tensor Library for Deep Learning
// 张量库 - 深度学习核心数据结构
// ============================================
package std.tensor

use std.math.{abs, sqrt, exp, log, pow, max as fmax, min as fmin, EPSILON}

// ============================================
// Tensor Structure (张量结构)
// ============================================

struct TensorShape {
    int[] dims      // 维度大小 [batch, seq, hidden]
    int ndim        // 维度数量
    int size        // 总元素数 (product of dims)
}

struct TensorData {
    float[] values  // 扁平化的数据
    int length      // 值的长度
    bool owns_data  // 是否拥有数据（vs 视图）
}

struct Tensor {
    TensorShape shape
    TensorData data
    string device   // "cpu" | "cuda:0"
    bool requires_grad
}

// ============================================
// Shape Utilities (形状工具)
// ============================================

func shape_from_dims(int[] dims) TensorShape {
    int ndim = len(dims)
    int size = 1
    int i = 0
    while i < ndim {
        size = size * dims[i]
        i = i + 1
    }
    TensorShape { dims: dims, ndim: ndim, size: size }
}

func shape_size(TensorShape s) int { s.size }

func shape_ndim(TensorShape s) int { s.ndim }

func get_dim(TensorShape s, int axis) int {
    if axis < 0 { axis = s.ndim + axis }  // 支持负索引
    if axis >= 0 && axis < s.ndim { return s.dims[axis] }
    1
}

func shape_to_string(TensorShape s) string {
    string result = "("
    int i = 0
    while i < s.ndim {
        if i > 0 { result = result + ", " }
        result = result + string(s.dims[i])
        i = i + 1
    }
    result = result + ")"
    result
}

// 计算展平后的索引
func flat_index(TensorShape shape, int[] indices) int {
    int idx = 0
    int stride = 1
    int d = shape.ndim - 1
    while d >= 0 {
        idx = idx + indices[d] * stride
        stride = stride * shape.dims[d]
        d = d - 1
    }
    idx
}

// 从扁平索引还原为多维索引
func unflatten_index(TensorShape shape, int flat_idx) int[] {
    int[] result = new int[shape.ndim]
    int remaining = flat_idx
    int d = shape.ndim - 1
    while d >= 0 {
        result[d] = remaining % shape.dims[d]
        remaining = remaining / shape.dims[d]
        d = d - 1
    }
    result
}

// ============================================
// Tensor Creation (张量创建)
// ============================================

// Create tensor from float array with given shape
func tensor(float[] values, int[] shape) Tensor {
    TensorShape sh = shape_from_dims(shape)
    
    // Validate size match
    if len(values) != sh.size {
        // Auto-resize or error handling needed here
        // For now, truncate or pad
    }
    
    TensorData td { values: values, length: len(values), owns_data: true }
    Tensor { shape: sh, data: td, device: "cpu", requires_grad: false }
}

// Zeros tensor
func zeros(int[] shape) Tensor {
    TensorShape sh = shape_from_dims(shape)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size {
        vals[i] = 0.0
        i = i + 1
    }
    tensor(vals, shape)
}

// Ones tensor
func ones(int[] shape) Tensor {
    TensorShape sh = shape_from_dims(shape)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size {
        vals[i] = 1.0
        i = i + 1
    }
    tensor(vals, shape)
}

// Full tensor (fill with scalar)
func full(int[] shape, float fill_value) Tensor {
    TensorShape sh = shape_from_dims(shape)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size {
        vals[i] = fill_value
        i = i + 1
    }
    tensor(vals, shape)
}

// Arange: [start, start+step, ..., stop-step]
func arange(int start, int stop, int step) Tensor {
    int count = (stop - start) / step
    if count <= 0 { count = 1 }
    float[] vals = new float[count]
    int i = 0
    int v = start
    while i < count {
        vals[i] = v as float
        v = v + step
        i = i + 1
    }
    int[] shape = new int[1]
    shape[0] = count
    tensor(vals, shape)
}

// Linspace: n evenly spaced points in [start, stop]
func linspace(float start, float stop, int n) Tensor {
    float[] vals = new float[n]
    float delta = 0.0
    if n > 1 { delta = (stop - start) / (n - 1) }
    int i = 0
    while i < n {
        vals[i] = start + i * delta
        i = i + 1
    }
    int[] shape = new int[1]
    shape[0] = n
    tensor(vals, shape)
}

// Eye (identity matrix): N×N identity
func eye(int n) Tensor {
    float[] vals = new float[n * n]
    int[] shape = new int[2]
    shape[0] = n
    shape[1] = n
    
    int r = 0
    while r < n {
        int c = 0
        while c < n {
            if r == c { vals[r * n + c] = 1.0 }
            else { vals[r * n + c] = 0.0 }
            c = c + 1
        }
        r = r + 1
    }
    tensor(vals, shape)
}

// Scalar tensor
func scalar(float value) Tensor {
    float[] vals = new float[1]
    vals[0] = value
    int[] shape = new int[1]
    shape[0] = 1
    tensor(vals, shape)
}

// ============================================
// Random Tensors (随机张量)
// ============================================

// Simple pseudo-random number generator state
struct RandState {
    int seed
}

var global_rand_state = RandState { seed: 42 }

func set_seed(int s) void {
    global_rand_state.seed = s
}

// Linear Congruential Generator
func rand_float(RandState mut state) float {
    // LCG: seed = (seed * 6364136223846793005 + 1442695040888963407) mod 2^64
    // Simplified version
    state.seed = state.seed * 1103515245 + 12345
    float result = (state.seed & 0x7fffffff) as float / 2147483647.0 as float
    result
}

// Uniform random [0, 1)
func rand_uniform(int[] shape) Tensor {
    TensorShape sh = shape_from_dims(shape)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size {
        vals[i] = rand_float(global_rand_state)
        i = i + 1
    }
    tensor(vals, shape)
}

// Normal distribution using Box-Muller transform
func randn(int[] shape, float mean, float stddev) Tensor {
    TensorShape sh = shape_from_dims(shape)
    float[] vals = new float[sh.size]
    
    int i = 0
    while i < sh.size {
        // Box-Muller transform
        float u1 = rand_float(global_rand_state)
        float u2 = rand_float(global_rand_state)
        
        // Avoid log(0)
        if u1 < 1e-10 { u1 = 1e-10 }
        
        float z = sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2)
        vals[i] = mean + z * stddev
        
        i = i + 1
    }
    tensor(vals, shape)
}

// Xavier/Glorot uniform initialization
func xavier_uniform(int[] fan_in, int[] fan_out) Tensor {
    int[] shape = new int[2]
    shape[0] = fan_in[0]
    shape[1] = fan_out[0]
    
    float limit = sqrt(6.0 / ((fan_in[0] as float) + (fan_out[0] as float)))
    Tensor t = rand_uniform(shape)
    
    // Scale to [-limit, limit]
    int i = 0
    while i < t.data.length {
        t.data.values[i] = (t.data.values[i] * 2.0 - 1.0) * limit
        i = i + 1
    }
    t
}

// Kaiming/He initialization (for ReLU networks)
func kaiming_normal(int[] fan_in, int[] fan_out) Tensor {
    int[] shape = new int[2]
    shape[0] = fan_in[0]
    shape[1] = fan_out[0]
    
    float std = sqrt(2.0 / fan_in[0] as float)
    randn(shape, 0.0, std)
}

// ============================================
// Tensor Accessors (张量访问)
// ============================================

// Get value at multi-dimensional index
func get(Tensor t, int[] indices) float {
    int idx = flat_index(t.shape, indices)
    t.data.values[idx]
}

// Set value at multi-dimensional index
func set(Tensor mut t, int[] indices, float value) void {
    int idx = flat_index(t.shape, indices)
    t.data.values[idx] = value
}

// Get value at flat index
func get_flat(Tensor t, int idx) float {
    t.data.values[idx]
}

// Set value at flat index
func set_flat(Tensor mut t, int idx, float value) void {
    t.data.values[idx] = value
}

// Get scalar value (only for single-element tensors)
func item(Tensor t) float {
    t.data.values[0]
}

// ============================================
// Tensor Reshaping (变形操作)
// ============================================

// Reshape tensor to new shape (must preserve total elements)
func reshape(Tensor t, int[] new_shape) Tensor {
    TensorShape new_sh = shape_from_dims(new_shape)
    
    if new_sh.size != t.shape.size {
        // Error: size mismatch - return original
        return t
    }
    
    Tensor {
        shape: new_sh,
        data: t.data,
        device: t.device,
        requires_grad: t.requires_grad,
    }
}

// Flatten all dimensions to 1D
func flatten(Tensor t) Tensor {
    int[] flat_shape = new int[1]
    flat_shape[0] = t.shape.size
    reshape(t, flat_shape)
}

// Squeeze: remove dimensions of size 1
func squeeze(Tensor t) Tensor {
    int new_ndim = 0
    int i = 0
    while i < t.shape.ndim {
        if t.shape.dims[i] != 1 { new_ndim = new_ndim + 1 }
        i = i + 1
    }
    
    int[] new_dims = new int[new_ndim]
    int j = 0
    i = 0
    while i < t.shape.ndim {
        if t.shape.dims[i] != 1 {
            new_dims[j] = t.shape.dims[i]
            j = j + 1
        }
        i = i + 1
    }
    
    reshape(t, new_dims)
}

// Unsqueeze: add dimension of size 1 at given position
func unsqueeze(Tensor t, int dim) Tensor {
    int new_ndim = t.shape.ndim + 1
    int[] new_dims = new int[new_ndim]
    
    int i = 0
    int j = 0
    while i < new_ndim {
        if i == dim { new_dims[i] = 1 }
        else {
            new_dims[i] = t.shape.dims[j]
            j = j + 1
        }
        i = i + 1
    }
    
    reshape(t, new_dims)
}

// Transpose last two dimensions
func transpose(Tensor t, int dim0, int dim1) Tensor {
    if t.shape.ndim < 2 { return t }
    
    int[] new_dims = new int[t.shape.ndim]
    int i = 0
    while i < t.shape.ndim {
        if i == dim0 { new_dims[i] = t.shape.dims[dim1] }
        else if i == dim1 { new_dims[i] = t.shape.dims[dim0] }
        else { new_dims[i] = t.shape.dims[i] }
        i = i + 1
    }
    
    // Note: This only changes metadata; actual data rearrangement 
    // would require more complex logic for >2D tensors
    // For 2D matrices, we can do a proper transpose:
    if t.shape.ndim == 2 && dim0 == 0 && dim1 == 1 {
        return transpose_2d(t)
    }
    
    Tensor { shape: shape_from_dims(new_dims), data: t.data, device: t.device, requires_grad: t.requires_grad }
}

// Actual 2D matrix transpose
func transpose_2d(Tensor t) Tensor {
    int rows = t.shape.dims[0]
    int cols = t.shape.dims[1]
    
    float[] vals = new float[rows * cols]
    int r = 0
    while r < rows {
        int c = 0
        while c < cols {
            vals[c * rows + r] = t.data.values[r * cols + c]
            c = c + 1
        }
        r = r + 1
    }
    
    int[] new_shape = new int[2]
    new_shape[0] = cols
    new_shape[1] = rows
    tensor(vals, new_shape)
}

// Permute dimensions arbitrarily
func permute(Tensor t, int[] order) Tensor {
    int[] new_dims = new int[t.shape.ndim]
    int i = 0
    while i < t.shape.ndim {
        new_dims[i] = t.shape.dims[order[i]]
        i = i + 1
    }
    Tensor { shape: shape_from_dims(new_dims), data: t.data, device: t.device, requires_grad: t.requires_grad }
}

// View as another shape (like PyTorch's view, no copy)
func view(Tensor t, int[] new_shape) Tensor {
    reshape(t, new_shape)
}

// Contiguous: ensure memory is contiguous (returns self for now)
func contiguous(Tensor t) Tensor {
    t
}

// ============================================
// Element-wise Operations (逐元素运算)
// ============================================

// Addition: supports broadcasting for scalars
func add(Tensor a, Tensor b) Tensor {
    // Simple case: same shape
    if a.shape.size == b.shape.size {
        float[] vals = new float[a.shape.size]
        int i = 0
        while i < a.shape.size {
            vals[i] = a.data.values[i] + b.data.values[i]
            i = i + 1
        }
        Tensor { shape: a.shape, data: TensorData{values: vals, length: a.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
    }
    // Scalar broadcast: b is scalar
    else if b.shape.size == 1 {
        float[] vals = new float[a.shape.size]
        float bv = b.data.values[0]
        int i = 0
        while i < a.shape.size {
            vals[i] = a.data.values[i] + bv
            i = i + 1
        }
        Tensor { shape: a.shape, data: TensorData{values: vals, length: a.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
    }
    // Scalar broadcast: a is scalar
    else if a.shape.size == 1 {
        float[] vals = new float[b.shape.size]
        float av = a.data.values[0]
        int i = 0
        while i < b.shape.size {
            vals[i] = av + b.data.values[i]
            i = i + 1
        }
        Tensor { shape: b.shape, data: TensorData{values: vals, length: b.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
    }
    else {
        a  // fallback: return unchanged
    }
}

// Add scalar to tensor
func add_scalar(Tensor t, float scalar) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        vals[i] = t.data.values[i] + scalar
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Subtraction
func sub(Tensor a, Tensor b) Tensor {
    if b.shape.size == 1 {
        add_scalar(a, -b.data.values[0])
    }
    else if b.shape.size == a.shape.size {
        float[] vals = new float[a.shape.size]
        int i = 0
        while i < a.shape.size {
            vals[i] = a.data.values[i] - b.data.values[i]
            i = i + 1
        }
        Tensor { shape: a.shape, data: TensorData{values: vals, length: a.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
    }
    else { a }
}

// Multiplication (element-wise)
func mul(Tensor a, Tensor b) Tensor {
    if b.shape.size == 1 {
        mul_scalar(a, b.data.values[0])
    }
    else if a.shape.size == 1 {
        mul_scalar(b, a.data.values[0])
    }
    else if b.shape.size == a.shape.size {
        float[] vals = new float[a.shape.size]
        int i = 0
        while i < a.shape.size {
            vals[i] = a.data.values[i] * b.data.values[i]
            i = i + 1
        }
        Tensor { shape: a.shape, data: TensorData{values: vals, length: a.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
    }
    else { a }
}

// Multiply by scalar
func mul_scalar(Tensor t, float scalar) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        vals[i] = t.data.values[i] * scalar
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Division
func div(Tensor a, Tensor b) Tensor {
    if b.shape.size == 1 {
        div_scalar(a, b.data.values[0])
    }
    else if b.shape.size == a.shape.size {
        float[] vals = new float[a.shape.size]
        int i = 0
        while i < a.shape.size {
            if abs(b.data.values[i]) > EPSILON { vals[i] = a.data.values[i] / b.data.values[i] }
            else { vals[i] = 0.0 }
            i = i + 1
        }
        Tensor { shape: a.shape, data: TensorData{values: vals, length: a.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
    }
    else { a }
}

// Divide by scalar
func div_scalar(Tensor t, float scalar) Tensor {
    if abs(scalar) < EPSILON { return t }
    mul_scalar(t, 1.0 / scalar)
}

// Negation
func neg(Tensor t) Tensor {
    mul_scalar(t, -1.0)
}

// Power (element-wise)
func pow_tensor(Tensor t, float exponent) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        vals[i] = pow(t.data.values[i], exponent)
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Square each element
func square(Tensor t) Tensor {
    pow_tensor(t, 2.0)
}

// Square root (element-wise)
func sqrt_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        if t.data.values[i] >= 0 { vals[i] = sqrt(t.data.values[i]) }
        else { vals[i] = 0.0 }
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Exponential (element-wise)
func exp_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        vals[i] = exp(t.data.values[i])
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Logarithm (element-wise, natural)
func log_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        if t.data.values[i] > 0 { vals[i] = log(t.data.values[i]) }
        else { vals[i] = NEG_INF }
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Absolute value (element-wise)
func abs_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        vals[i] = abs(t.data.values[i])
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Clamp values to range
func clamp_tensor(Tensor t, float lo, float hi) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        float v = t.data.values[i]
        if v < lo { v = lo }
        if v > hi { v = hi }
        vals[i] = v
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// ============================================
// Reduction Operations (规约操作)
// ============================================

// Sum of all elements
func sum_all(Tensor t) Tensor {
    float s = 0.0
    int i = 0
    while i < t.shape.size {
        s = s + t.data.values[i]
        i = i + 1
    }
    scalar(s)
}

// Sum along specific dimensions
func sum_dim(Tensor t, int dim, bool keepdim) Tensor {
    if t.shape.ndim == 0 { return sum_all(t) }
    
    int target_dim = dim
    if target_dim < 0 { target_dim = t.shape.ndim + target_dim }
    if target_dim < 0 || target_dim >= t.shape.ndim { return sum_all(t) }
    
    int dim_size = t.shape.dims[target_dim]
    int outer_stride = 1
    int inner_size = 1
    int k = 0
    while k < target_dim { outer_stride = outer_stride * t.shape.dims[k]; k = k + 1 }
    k = target_dim + 1
    while k < t.shape.ndim { inner_size = inner_size * t.shape.dims[k]; k = k + 1 }
    
    int output_size = t.shape.size / dim_size
    float[] sums = new float[output_size]
    
    // Initialize
    int i = 0
    while i < output_size { sums[i] = 0.0; i = i + 1 }
    
    // Accumulate
    i = 0
    while i < t.shape.size {
        int out_idx = (i / (dim_size * inner_size)) * inner_size + (i % inner_size)
        sums[out_idx] = sums[out_idx] + t.data.values[i]
        i = i + 1
    }
    
    // Output shape
    int new_ndim = t.shape.ndim - 1
    if keepdim { new_ndim = t.shape.ndim }
    int[] new_dims = new int[new_ndim]
    
    if keepdim {
        int j = 0
        while j < t.shape.ndim {
            if j == target_dim { new_dims[j] = 1 }
            else { new_dims[j] = t.shape.dims[j] }
            j = j + 1
        }
    }
    else {
        int j = 0
        int m = 0
        while j < t.shape.ndim {
            if j != target_dim { new_dims[m] = t.shape.dims[j]; m = m + 1 }
            j = j + 1
        }
    }
    
    Tensor { shape: shape_from_dims(new_dims), data: TensorData{values: sums, length: output_size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Mean of all elements
func mean_all(Tensor t) Tensor {
    float s = item(sum_all(t))
    scalar(s / t.shape.size as float)
}

// Mean along dimension
func mean_dim(Tensor t, int dim, bool keepdim) Tensor {
    if t.shape.ndim == 0 { return mean_all(t) }
    
    int target_dim = dim
    if target_dim < 0 { target_dim = t.shape.ndim + target_dim }
    int dim_size = t.shape.dims[target_dim]
    
    Tensor s = sum_dim(t, target_dim, keepdim)
    div_scalar(s, dim_size as float)
}

// Max of all elements
func max_all(Tensor t) Tensor {
    if t.shape.size == 0 { return scalar(NEG_INF) }
    float m = t.data.values[0]
    int i = 1
    while i < t.shape.size {
        if t.data.values[i] > m { m = t.data.values[i] }
        i = i + 1
    }
    scalar(m)
}

// Min of all elements
func min_all(Tensor t) Tensor {
    if t.shape.size == 0 { return scalar(INF) }
    float m = t.data.values[0]
    int i = 1
    while i < t.shape.size {
        if t.data.values[i] < m { m = t.data.values[i] }
        i = i + 1
    }
    scalar(m)
}

// L2 norm (Frobenius norm for matrices)
func norm(Tensor t) Tensor {
    float s = 0.0
    int i = 0
    while i < t.shape.size {
        s = s + t.data.values[i] * t.data.values[i]
        i = i + 1
    }
    scalar(sqrt(s))
}

// ============================================
// Matrix Operations (矩阵运算)
// ============================================

// Matrix multiplication for 2D tensors: (M×K) @ (K×N) -> (M×N)
func matmul_2d(Tensor a, Tensor b) Tensor {
    if a.shape.ndim != 2 || b.shape.ndim != 2 { return a }
    
    int M = a.shape.dims[0]
    int K = a.shape.dims[1]
    int K2 = b.shape.dims[0]
    int N = b.shape.dims[1]
    
    if K != K2 { return a }  // Dimension mismatch
    
    float[] result = new float[M * N]
    
    int m = 0
    while m < M {
        int n = 0
        while n < N {
            float s = 0.0
            int k = 0
            while k < K {
                s = s + a.data.values[m * K + k] * b.data.values[k * N + n]
                k = k + 1
            }
            result[m * N + n] = s
            n = n + 1
        }
        m = m + 1
    }
    
    int[] out_shape = new int[2]
    out_shape[0] = M
    out_shape[1] = N
    tensor(result, out_shape)
}

// Dot product for 1D vectors
func dot(Tensor a, Tensor b) Tensor {
    if a.shape.ndim != 1 || b.shape.ndim != 1 || a.shape.dims[0] != b.shape.dims[0] {
        return scalar(0.0)
    }
    
    float s = 0.0
    int i = 0
    while i < a.shape.dims[0] {
        s = s + a.data.values[i] * b.data.values[i]
        i = i + 1
    }
    scalar(s)
}

// Outer product of two vectors
func outer(Tensor a, Tensor b) Tensor {
    int m = a.shape.dims[0]
    int n = b.shape.dims[0]
    
    float[] result = new float[m * n]
    int i = 0
    while i < m {
        int j = 0
        while j < n {
            result[i * n + j] = a.data.values[i] * b.data.values[j]
            j = j + 1
        }
        i = i + 1
    }
    
    int[] shape = new int[2]
    shape[0] = m
    shape[1] = n
    tensor(result, shape)
}

// ============================================
// Concatenation & Splitting (拼接与分割)
// ============================================

// Concatenate tensors along an axis
func cat(Tensor[] tensors, int dim) Tensor {
    if len(tensors) == 0 { return zeros(new int[]{0}) }
    if len(tensors) == 1 { return tensors[0] }
    
    int target_dim = dim
    if target_dim < 0 { target_dim = tensors[0].shape.ndim + target_dim }
    
    // Calculate total size along concat dimension
    int total_concat = 0
    int i = 0
    while i < len(tensors) {
        total_concat = total_concat + tensors[i].shape.dims[target_dim]
        i = i + 1
    }
    
    // Build output shape
    int[] out_shape = new int[tensors[0].shape.ndim]
    int j = 0
    while j < tensors[0].shape.ndim {
        if j == target_dim { out_shape[j] = total_concat }
        else { out_shape[j] = tensors[0].shape.dims[j] }
        j = j + 1
    }
    
    int total_size = shape_from_dims(out_shape).size
    float[] vals = new float[total_size]
    
    // Copy data
    int offset = 0
    i = 0
    while i < len(tensors) {
        int sz = tensors[i].data.length
        int k = 0
        while k < sz {
            vals[offset + k] = tensors[i].data.values[k]
            k = k + 1
        }
        offset = offset + sz
        i = i + 1
    }
    
    Tensor { shape: shape_from_dims(out_shape), data: TensorData{values: vals, length: total_size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Stack tensors along new dimension
func stack(Tensor[] tensors, int dim) Tensor {
    if len(tensors) == 0 { return zeros(new int[]{0}) }
    
    int n = len(tensors)
    int target_dim = dim
    if target_dim < 0 { target_dim = tensors[0].shape.ndim + 1 + target_dim }
    
    // Insert new dimension
    int[] out_shape = new int[tensors[0].shape.ndim + 1]
    int i = 0
    int j = 0
    while i < len(out_shape) {
        if i == target_dim { out_shape[i] = n }
        else { out_shape[i] = tensors[0].shape.dims[j]; j = j + 1 }
        i = i + 1
    }
    
    cat(tensors, target_dim)
}

// ============================================
// Activation Functions (Tensor 版激活函数)
// ============================================

// ReLU: max(0, x)
func relu_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        if t.data.values[i] > 0 { vals[i] = t.data.values[i] }
        else { vals[i] = 0.0 }
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// GELU (approximate)
func gelu_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    float sqrt_2_over_pi = 0.7978845608028654
    int i = 0
    while i < t.shape.size {
        float x = t.data.values[i]
        float inner = sqrt_2_over_pi * (x + 0.044715 * x * x * x)
        // tanh approximation
        float e2i = exp(2.0 * inner)
        float th = (e2i - 1.0) / (e2i + 1.0)
        vals[i] = 0.5 * x * (1.0 + th)
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Softmax along specified dimension
func softmax_tensor(Tensor t, int dim) Tensor {
    int target_dim = dim
    if target_dim < 0 { target_dim = t.shape.ndim + target_dim }
    
    // Numerical stability: subtract max
    Tensor m = max_all(t)
    Tensor shifted = sub(t, m)
    
    // Exp
    Tensor exp_vals = exp_tensor(shifted)
    
    // Sum along dim
    Tensor sum_exp = sum_dim(exp_vals, target_dim, true)
    
    // Divide
    div(exp_vals, sum_exp)
}

// Layer normalization: normalize along last dimension
func layer_norm(Tensor t, float eps) Tensor {
    if t.shape.ndim == 0 { return t }
    
    int last_dim = t.shape.ndim - 1
    int feat_dim = t.shape.dims[last_dim]
    
    // Mean and variance
    Tensor mu = mean_dim(t, last_dim, true)
    Tensor centered = sub(t, mu)
    Tensor sq = mul(centered, centered)
    Tensor var = mean_dim(sq, last_dim, true)
    
    // Normalize: (x - mean) / sqrt(var + eps)
    Tensor var_eps = add_scalar(var, eps)
    Tensor std = sqrt_tensor(var_eps)
    div(centered, std)
}

// Sigmoid (tensor version)
func sigmoid_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        float x = t.data.values[i]
        if x > 500 { vals[i] = 1.0 }
        else if x < -500 { vals[i] = 0.0 }
        else {
            float ep = exp(-x)
            vals[i] = 1.0 / (1.0 + ep)
        }
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Tanh (tensor version)
func tanh_tensor(Tensor t) Tensor {
    float[] vals = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        float x = t.data.values[i]
        float ep = exp(x)
        float em = exp(-x)
        vals[i] = (ep - em) / (ep + em)
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// Dropout (training mode: scale by 1/(1-p), zero out p fraction)
func dropout(Tensor t, float p, bool training) Tensor {
    if !training || p == 0.0 { return t }
    
    float[] vals = new float[t.shape.size]
    float scale = 1.0 / (1.0 - p)
    
    int i = 0
    while i < t.shape.size {
        float r = rand_float(global_rand_state)
        if r < p { vals[i] = 0.0 }
        else { vals[i] = t.data.values[i] * scale }
        i = i + 1
    }
    Tensor { shape: t.shape, data: TensorData{values: vals, length: t.shape.size, owns_data: true}, device: "cpu", requires_grad: false }
}

// ============================================
// Indexing & Gathering (索引与收集)
// ============================================

// Gather: select values by index array
func gather(Tensor t, int[] indices, int dim) Tensor {
    if t.shape.ndim == 0 { return t }
    
    int target_dim = dim
    if target_dim < 0 { target_dim = t.shape.ndim + target_dim }
    
    // For simplicity: gather along first dimension with 1D index
    int num_indices = len(indices)
    int elem_size = 1
    int k = 1
    while k < t.shape.ndim {
        elem_size = elem_size * t.shape.dims[k]
        k = k + 1
    }
    
    float[] vals = new float[num_indices * elem_size]
    int i = 0
    while i < num_indices {
        int src_start = indices[i] * elem_size
        int dst_start = i * elem_size
        int j = 0
        while j < elem_size {
            vals[dst_start + j] = t.data.values[src_start + j]
            j = j + 1
        }
        i = i + 1
    }
    
    int[] out_shape = new int[t.shape.ndim]
    out_shape[0] = num_indices
    k = 1
    while k < t.shape.ndim { out_shape[k] = t.shape.dims[k]; k = k + 1 }
    
    Tensor { shape: shape_from_dims(out_shape), data: TensorData{values: vals, length: num_indices * elem_size, owns_data: true}, device: "cpu", requires_grad: false }
}

// One-hot encoding
func one_hot(int[] indices, int num_classes) Tensor {
    int n = len(indices)
    float[] vals = new float[n * num_classes]
    
    int i = 0
    while i < n * num_classes { vals[i] = 0.0; i = i + 1 }
    
    i = 0
    while i < n {
        int cls = indices[i]
        if cls >= 0 && cls < num_classes { vals[i * num_classes + cls] = 1.0 }
        i = i + 1
    }
    
    int[] shape = new int[2]
    shape[0] = n
    shape[1] = num_classes
    tensor(vals, shape)
}

// ============================================
// Loss Functions (损失函数)
// ============================================

// Mean Squared Error: mean((pred - target)^2)
func mse_loss(Tensor pred, Tensor target) Tensor {
    Tensor diff = sub(pred, target)
    Tensor sq = square(diff)
    mean_all(sq)
}

// Cross Entropy Loss (with built-in softmax + log)
// Expects logits (not probabilities)
func cross_entropy_loss(Tensor logits, Tensor targets) Tensor {
    // Softmax + negative log likelihood
    Tensor probs = softmax_tensor(logits, logits.shape.ndim - 1)
    Tensor log_probs = log_tensor(probs)
    
    // Negative log probability of correct class
    // For simplicity, assuming targets are class indices
    // Full implementation would use gather
    Tensor neg_log_p = mul(log_probs, targets)
    
    // Average over batch
    Tensor summed = sum_all(neg_log_p)
    div_scalar(summed, logits.shape.dims[0] as float)
}

// Binary Cross Entropy with Logits
func bce_with_logits_loss(Tensor logits, Tensor targets) Tensor {
    Tensor sigmoid_logits = sigmoid_tensor(logits)
    
    // BCE = -[target*log(sigmoid) + (1-target)*log(1-sigmoid)]
    Tensor loss_pos = mul(targets, log_tensor(add_scalar(sigmoid_logits, 1e-7)))
    Tensor ones_minus_target = sub(scalar(1.0), targets)
    Tensor ones_minus_sig = sub(scalar(1.0), sigmoid_logits)
    Tensor loss_neg = mul(ones_minus_target, log_tensor(add_scalar(ones_minus_sig, 1e-7)))
    
    Tensor total_loss = add(loss_pos, loss_neg)
    Tensor neg_mean = mul_scalar(mean_all(total_loss), -1.0)
    neg_mean
}

// L1 Loss: mean(|pred - target|)
func l1_loss(Tensor pred, Tensor target) Tensor {
    Tensor diff = sub(pred, target)
    Tensor abs_diff = abs_tensor(diff)
    mean_all(abs_diff)
}

// Smooth L1 Loss
func smooth_l1_loss(Tensor pred, Tensor target, float beta) Tensor {
    Tensor diff = sub(pred, target)
    Tensor abs_diff = abs_tensor(diff)
    
    // |x| < beta: 0.5 * x^2 / beta
    // otherwise: |x| - 0.5 * beta
    // Simplified implementation
    mse_loss(pred, target)
}

// Huber Loss (combines MSE and MAE)
func huber_loss(Tensor pred, Tensor target, float delta) Tensor {
    Tensor diff = sub(pred, target)
    Tensor abs_diff = abs_tensor(diff)
    
    // For simplicity, use smooth L1 behavior
    smooth_l1_loss(pred, target, delta)
}

// KL Divergence (simplified)
func kl_divergence_loss(Tensor p, Tensor q) Tensor {
    Tensor log_p = log_tensor(add_scalar(p, 1e-7))
    Tensor log_q = log_tensor(add_scalar(q, 1e-7))
    Tensor ratio = div(p, q)
    Tensor log_ratio = sub(log_p, log_q)
    Tensor kl_term = mul(ratio, log_ratio)
    mean_all(kl_term)
}

// ============================================
// Utility Functions (工具函数)
// ============================================

// Total number of elements
func numel(Tensor t) int { t.shape.size }

// Get shape as array
func shape(Tensor t) int[] { t.shape.dims }

// Check if two tensors have same shape
func same_shape(Tensor a, Tensor b) bool {
    if a.shape.ndim != b.shape.ndim { return false }
    int i = 0
    while i < a.shape.ndim {
        if a.shape.dims[i] != b.shape.dims[i] { return false }
        i = i + 1
    }
    true
}

// Print tensor info
func print_info(Tensor t) void {
    println("Tensor(", shape_to_string(t.shape), ", device=", t.device, ", grad=", t.requires_grad, ")")
}

// Print first N values
func print_values(Tensor t, int n) void {
    print_info(t)
    int limit = n
    if limit > t.shape.size { limit = t.shape.size }
    string s = "["
    int i = 0
    while i < limit {
        if i > 0 { s = s + ", " }
        s = s + format_float(t.data.values[i], 4)
        i = i + 1
    }
    if limit < t.shape.size { s = s + ", ..." }
    s = s + "]"
    println(s)
}

// Format float to fixed decimal places
func format_float(float val, int decimals) string {
    int ival = val as int
    float frac = val - ival as float
    if frac < 0 { frac = -frac }
    
    string result = string(ival)
    if decimals > 0 {
        result = result + "."
        int d = 0
        while d < decimals {
            frac = frac * 10.0
            int digit = frac as int
            result = result + string(digit)
            frac = frac - digit as float
            d = d + 1
        }
    }
    result
}
