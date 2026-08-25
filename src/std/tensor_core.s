package std.tensor_core
const FLOAT_EPSILON = 1e-7
const FLOAT_INF = 1e308
const FLOAT_NEG_INF = -1e308

struct tensor_shape {
    int[] dims
    int ndim
    int size
}

struct tensor {
    tensor_shape shape
    float[] data
    string device
    bool requires_grad
}

func make_shape(int[] dims) tensor_shape {
    int ndim = len(dims)
    int total_size = 1
    int i = 0
    for i < ndim {
        total_size = total_size * dims[i]
        i = i + 1
    }
    tensor_shape { dims: dims, ndim: ndim, size: total_size }
}

func numel(tensor t) int { t.shape.size }

func ndim(tensor t) int { t.shape.ndim }

func dim_size(tensor t, int axis) int {
    if axis < 0 { axis = t.shape.ndim + axis }
    if axis >= 0 && axis < t.shape.ndim { return t.shape.dims[axis] }
    return 1
}

func shape_str(tensor_shape s) string {
    string result = "("
    int i = 0
    for i < s.ndim {
        if i > 0 { result = result + ", " }
        result = result + int_to_string(s.dims[i])
        i = i + 1
    }
    result = result + ")"
    result
}

func same_shape(tensor a, tensor b) bool {
    if a.shape.ndim != b.shape.ndim { return false }
    int i = 0
    for i < a.shape.ndim {
        if a.shape.dims[i] != b.shape.dims[i] { return false }
        i = i + 1
    }
    return true
}

func flat_index(tensor_shape shape, int[] indices) int {
    int idx = 0
    int stride = 1
    int d = shape.ndim - 1
    for d >= 0 {
        idx = idx + indices[d] * stride
        stride = stride * shape.dims[d]
        d = d - 1
    }
    idx
}

func unflatten_index(tensor_shape shape, int flat_idx) int[] {
    int[] result = new int[shape.ndim]
    int remaining = flat_idx
    int d = shape.ndim - 1
    for d >= 0 {
        (d) = remaining % shape.dims[d]
        remaining = remaining / shape.dims[d]
        d = d - 1
    }
    result
}

func make_tensor(float[] values, int[] shape_dims) tensor {
    tensor_shape sh = make_shape(shape_dims)
    int val_count = len(values)
    if val_count < sh.size {
        float[] padded = new float[sh.size]
        int i = 0
        for i < val_count { padded[i] = values[i]; i = i + 1 }
        for i < sh.size { padded[i] = 0.0; i = i + 1 }
        values = padded
    }
    tensor { shape: sh, data: values, device: "cpu", requires_grad: false }
}

func zeros(int[] shape_dims) tensor {
    tensor_shape sh = make_shape(shape_dims)
    float[] vals = new float[sh.size]
    int i = 0
    for i < sh.size { vals[i] = 0.0; i = i + 1 }
    tensor { shape: sh, data: vals, device: "cpu", requires_grad: false }
}

func ones(int[] shape_dims) tensor {
    tensor_shape sh = make_shape(shape_dims)
    float[] vals = new float[sh.size]
    int i = 0
    for i < sh.size { vals[i] = 1.0; i = i + 1 }
    tensor { shape: sh, data: vals, device: "cpu", requires_grad: false }
}

func full(int[] shape_dims, float fill_value) tensor {
    tensor_shape sh = make_shape(shape_dims)
    float[] vals = new float[sh.size]
    int i = 0
    for i < sh.size { vals[i] = fill_value; i = i + 1 }
    tensor { shape: sh, data: vals, device: "cpu", requires_grad: false }
}

func scalar(float value) tensor {
    float[] v = new float[1]
    v[0] = value
    int[] s = new int[1]
    s[0] = 1
    tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func arange(int start, int stop, int step) tensor {
    int count = (stop - start) / step
    if count <= 0 { count = 1 }
    float[] v = new float[count]
    int i = 0
    int val = start
    for i < count {
        v[i] = val as float
        val = val + step
        i = i + 1
    }
    int[] s = new int[1]
    s[0] = count
    tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func linspace(float start, float stop, int n) tensor {
    float[] v = new float[n]
    float delta = 0.0
    if n > 1 { delta = (stop - start) / ((n-1) as float) }
    int i = 0
    for i < n {
        v[i] = start + (i as float) * delta
        i = i + 1
    }
    int[] s = new int[1]
    s[0] = n
    tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func eye(int n) tensor {
    int[] shape = new int[2]
    shape[0] = n
    shape[1] = n
    tensor_shape sh = make_shape(shape)
    float[] v = new float[sh.size]
    int r = 0
    for r < n {
        int c = 0
        for c < n {
            if r == c { v[r * n + c] = 1.0 }
            else { v[r * n + c] = 0.0 }
            c = c + 1
        }
        r = r + 1
    }
    tensor { shape: sh, data: v, device: "cpu", requires_grad: false }
}

func zeros_like(tensor t) tensor { zeros(t.shape.dims) }

func ones_like(tensor t) tensor { ones(t.shape.dims) }
var _rand_seed = 42

func set_seed(int seed) void { _rand_seed = seed }

func _rand_float() float {
    _rand_seed = _rand_seed * 1103515245 + 12345
    float r = (_rand_seed & 0x7fffffff) as float / 2147483647.0
    r
}

func rand(int[] shape_dims) tensor {
    tensor_shape sh = make_shape(shape_dims)
    float[] v = new float[sh.size]
    int i = 0
    for i < sh.size { v[i] = _rand_float(); i = i + 1 }
    tensor { shape: sh, data: v, device: "cpu", requires_grad: false }
}

func randn(int[] shape_dims, float mean, float std) tensor {
    tensor_shape sh = make_shape(shape_dims)
    float[] v = new float[sh.size]
    int i = 0
    for i < sh.size {
        float u1 = _rand_float()
        float u2 = _rand_float()
        if u1 < 1e-10 { u1 = 1e-10 }
        float z = sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2)
        v[i] = mean + z * std
        i = i + 1
    }
    tensor { shape: sh, data: v, device: "cpu", requires_grad: false }
}

func xavier_uniform(int fan_in, int fan_out) tensor {
    int[] shape = new int[2]
    shape[0] = fan_in
    shape[1] = fan_out
    float limit = sqrt(6.0 / ((fan_in as float) + (fan_out as float)))
    tensor t = rand(shape)
    int i = 0
    for i < t.shape.size {
        t.data[i] = (t.data[i] * 2.0 - 1.0) * limit
        i = i + 1
    }
    t
}

func kaiming_normal(int fan_in, int fan_out) tensor {
    int[] shape = new int[2]
    shape[0] = fan_in
    shape[1] = fan_out
    float std_val = sqrt(2.0 / fan_in as float)
    randn(shape, 0.0, std_val)
}

func item(tensor t) float {
    t.data[0]
}

func get(tensor t, int[] indices) float {
    int idx = flat_index(t.shape, indices)
    t.data[idx]
}

func get_flat(tensor t, int idx) float {
    t.data[idx]
}

func set_flat(tensor t, int idx, float value) void {
    t.data[idx] = value
}

func print_tensor_info(tensor t) void {
    print("tensor" + shape_str(t.shape) + " device=" + t.device)
}

func print_values(tensor t, int n) void {
    print_tensor_info(t)
    int limit = n
    if limit > t.shape.size { limit = t.shape.size }
    string s = "["
    int i = 0
    for i < limit {
        if i > 0 { s = s + ", " }
        s = s + fmt_float(t.data[i], 4)
        i = i + 1
    }
    if limit < t.shape.size { s = s + ", ..." }
    s = s + "]"
    println(s)
}

func reshape(tensor t, int[] new_dims) tensor {
    tensor_shape new_sh = make_shape(new_dims)
    if new_sh.size != t.shape.size {
        return t
    }
    tensor { shape: new_sh, data: t.data, device: t.device, requires_grad: t.requires_grad }
}

func flatten(tensor t) tensor {
    int[] flat_s = new int[1]
    flat_s[0] = t.shape.size
    reshape(t, flat_s)
}

func squeeze(tensor t) tensor {
    int new_ndim = 0
    int i = 0
    for i < t.shape.ndim {
        if t.shape.dims[i] != 1 { new_ndim = new_ndim + 1 }
        i = i + 1
    }
    int[] new_dims = new int[new_ndim]
    int j = 0
    i = 0
    for i < t.shape.ndim {
        if t.shape.dims[i] != 1 {
            new_dims[j] = t.shape.dims[i]
            j = j + 1
        }
        i = i + 1
    }
    reshape(t, new_dims)
}

func unsqueeze(tensor t, int dim_pos) tensor {
    int new_ndim = t.shape.ndim + 1
    int[] new_dims = new int[new_ndim]
    int i = 0
    int j = 0
    for i < new_ndim {
        if i == dim_pos { new_dims[i] = 1 }
        else {
            new_dims[i] = t.shape.dims[j]
            j = j + 1
        }
        i = i + 1
    }
    reshape(t, new_dims)
}

func transpose_2d(tensor t) tensor {
    if t.shape.ndim != 2 { return t }
    int rows = t.shape.dims[0]
    int cols = t.shape.dims[1]
    float[] v = new float[t.shape.size]
    int r = 0
    for r < rows {
        int c = 0
        for c < cols {
            v[c * rows + r] = t.data[r * cols + c]
            c = c + 1
        }
        r = r + 1
    }
    int[] new_s = new int[2]
    new_s[0] = cols
    new_s[1] = rows
    tensor { shape: make_shape(new_s), data: v, device: t.device, requires_grad: t.requires_grad }
}

func transpose(tensor t, int dim0, int dim1) tensor {
    if t.shape.ndim == 2 { return transpose_2d(t) }
    int[] new_dims = new int[t.shape.ndim]
    int i = 0
    for i < t.shape.ndim {
        if i == dim0 { new_dims[i] = t.shape.dims[dim1] }
        else if i == dim1 { new_dims[i] = t.shape.dims[dim0] }
        else { new_dims[i] = t.shape.dims[i] }
        i = i + 1
    }
    tensor { shape: make_shape(new_dims), data: t.data, device: t.device, requires_grad: t.requires_grad }
}

func view(tensor t, int[] new_dims) tensor {
    reshape(t, new_dims)
}

func contiguous(tensor t) tensor { t }

func add(tensor a, tensor b) tensor {
    if same_shape(a, b) {
        return elemwise_op2(a, b, func(float x, float y) float { x + y })
    }
    if is_scalar(b) { return add_scalar(a, item(b)) }
    if is_scalar(a) { return add_scalar(b, item(a)) }
    a
}

func add_scalar(tensor t, float s) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { v[i] = t.data[i] + s; i = i + 1 }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func sub(tensor a, tensor b) tensor {
    if is_scalar(b) { return add_scalar(a, -item(b)) }
    if same_shape(a, b) { return elemwise_op2(a, b, func(float x, float y) float { x - y }) }
    if is_scalar(a) { return neg(add_scalar(b, -item(a))) }
    a
}

func mul(tensor a, tensor b) tensor {
    if is_scalar(b) { return mul_scalar(a, item(b)) }
    if is_scalar(a) { return mul_scalar(b, item(a)) }
    if same_shape(a, b) { return elemwise_op2(a, b, func(float x, float y) float { x * y }) }
    a
}

func mul_scalar(tensor t, float s) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { v[i] = t.data[i] * s; i = i + 1 }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func div(tensor a, tensor b) tensor {
    if is_scalar(b) { return div_scalar(a, item(b)) }
    if same_shape(a, b) {
        return elemwise_op2(a, b, func(float x, float y) float { 
            if abs(y) < FLOAT_EPSILON { return 0.0 }
            x / y 
        })
    }
    a
}

func div_scalar(tensor t, float s) tensor {
    if abs(s) < FLOAT_EPSILON { return t }
    mul_scalar(t, 1.0 / s)
}

func neg(tensor t) tensor { mul_scalar(t, -1.0) }

func pow_t(tensor t, float exp) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { v[i] = pow_f(t.data[i], exp); i = i + 1 }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func square(tensor t) tensor { pow_t(t, 2.0) }

func sqrt_t(tensor t) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { 
        if t.data[i] >= 0 { v[i] = sqrt_f(t.data[i]) }
        else { v[i] = 0.0 }
        i = i + 1
    }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func exp_t(tensor t) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { v[i] = exp_f(t.data[i]); i = i + 1 }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func log_t(tensor t) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { 
        if t.data[i] > 0 { v[i] = log_f(t.data[i]) }
        else { v[i] = FLOAT_NEG_INF }
        i = i + 1
    }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func abs_t(tensor t) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size { v[i] = abs_f(t.data[i]); i = i + 1 }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func clamp_t(tensor t, float lo, float hi) tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size {
        float x = t.data[i]
        if x < lo { x = lo }
        if x > hi { x = hi }
        v[i] = x
        i = i + 1
    }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func is_scalar(tensor t) bool { t.shape.size == 1 }

func elemwise_op2(tensor a, tensor b, func(float, float) float op) tensor {
    int n = a.shape.size
    float[] v = new float[n]
    int i = 0
    for i < n { v[i] = op(a.data[i], b.data[i]); i = i + 1 }
    tensor { shape: a.shape, data: v, device: "cpu", requires_grad: false }
}

func elemwise_op1(tensor t, func(float) float op) tensor {
    int n = t.shape.size
    float[] v = new float[n]
    int i = 0
    for i < n { v[i] = op(t.data[i]); i = i + 1 }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func sum_all(tensor t) tensor {
    float s = 0.0
    int i = 0
    for i < t.shape.size { s = s + t.data[i]; i = i + 1 }
    scalar(s)
}

func sum_dim(tensor t, int target_dim, bool keepdim) tensor {
    if t.shape.ndim == 0 { return sum_all(t) }
    int d = target_dim
    if d < 0 { d = t.shape.ndim + d }
    if d < 0 || d >= t.shape.ndim { return sum_all(t) }
    int d_size = t.shape.dims[d]
    int out_n = t.shape.size / d_size
    float[] sums = new float[out_n]
    int i = 0
    for i < out_n { sums[i] = 0.0; i = i + 1 }
    i = 0
    for i < t.shape.size {
        int oi = reduce_idx_sum(i, t.shape, d)
        sums[oi] = sums[oi] + t.data[i]
        i = i + 1
    }
    int new_ndim = t.shape.ndim
    if !keepdim { new_ndim = new_ndim - 1 }
    int[] out_d = build_reduced_shape(t.shape, d, keepdim)
    tensor { shape: make_shape(out_d), data: sums, device: "cpu", requires_grad: false }
}

func mean_all(tensor t) tensor {
    float s = item(sum_all(t))
    scalar(s / t.shape.size as float)
}

func mean_dim(tensor t, int dim, bool keepdim) tensor {
    if t.shape.ndim == 0 { return mean_all(t) }
    int d = dim
    if d < 0 { d = t.shape.ndim + d }
    int d_size = t.shape.dims[d]
    tensor s = sum_dim(t, d, keepdim)
    div_scalar(s, d_size as float)
}

func max_all(tensor t) tensor {
    if t.shape.size == 0 { return scalar(FLOAT_NEG_INF) }
    float m = t.data[0]
    int i = 1
    for i < t.shape.size {
        if t.data[i] > m { m = t.data[i] }
        i = i + 1
    }
    scalar(m)
}

func min_all(tensor t) tensor {
    if t.shape.size == 0 { return scalar(FLOAT_INF) }
    float m = t.data[0]
    int i = 1
    for i < t.shape.size {
        if t.data[i] < m { m = t.data[i] }
        i = i + 1
    }
    scalar(m)
}

func norm(tensor t) tensor {
    float s = 0.0
    int i = 0
    for i < t.shape.size { s = s + t.data[i] * t.data[i]; i = i + 1 }
    scalar(sqrt_f(s))
}

func matmul(tensor a, tensor b) tensor {
    if a.shape.ndim != 2 || b.shape.ndim != 2 { return a }
    int M = a.shape.dims[0]
    int K = a.shape.dims[1]
    int K2 = b.shape.dims[0]
    int N = b.shape.dims[1]
    if K != K2 { return a }
    float[] v = new float[M * N]
    int m = 0
    for m < M {
        int n = 0
        for n < N {
            float s = 0.0
            int k = 0
            for k < K {
                s = s + a.data[m * K + k] * b.data[k * N + n]
                k = k + 1
            }
            v[m * N + n] = s
            n = n + 1
        }
        m = m + 1
    }
    int[] out_s = new int[2]
    out_s[0] = M
    out_s[1] = N
    tensor { shape: make_shape(out_s), data: v, device: "cpu", requires_grad: false }
}

func dot(tensor a, tensor b) tensor {
    if a.shape.ndim != 1 || b.shape.ndim != 1 { return scalar(0.0) }
    int n = a.shape.dims[0]
    if n != b.shape.dims[0] { return scalar(0.0) }
    float s = 0.0
    int i = 0
    for i < n { s = s + a.data[i] * b.data[i]; i = i + 1 }
    scalar(s)
}

func outer(tensor a, tensor b) tensor {
    int m = a.shape.dims[0]
    int n = b.shape.dims[0]
    float[] v = new float[m * n]
    int i = 0
    for i < m {
        int j = 0
        for j < n {
            v[i * n + j] = a.data[i] * b.data[j]
            j = j + 1
        }
        i = i + 1
    }
    int[] s = new int[2]
    s[0] = m
    s[1] = n
    tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func cat(tensor[] tensors, int axis) tensor {
    if len(tensors) == 0 { return zeros({0}) }
    if len(tensors) == 1 { return tensors[0] }
    int d = axis
    if d < 0 { d = tensors[0].shape.ndim + d }
    int concat_total = 0
    int ti = 0
    for ti < len(tensors) { 
        concat_total = concat_total + tensors[ti].shape.dims[d]
        ti = ti + 1 
    }
    int[] out_d = new int[tensors[0].shape.ndim]
    int i = 0
    for i < tensors[0].shape.ndim {
        if i == d { out_d[i] = concat_total }
        else { out_d[i] = tensors[0].shape.dims[i] }
        i = i + 1
    }
    int total_sz = make_shape(out_d).size
    float[] v = new float[total_sz]
    int offset = 0
    ti = 0
    for ti < len(tensors) {
        int sz = tensors[ti].shape.size
        int j = 0
        for j < sz { v[offset + j] = tensors[ti].data[j]; j = j + 1 }
        offset = offset + sz
        ti = ti + 1
    }
    tensor { shape: make_shape(out_d), data: v, device: "cpu", requires_grad: false }
}

func relu(tensor t) tensor {
    elemwise_op1(t, func(float x) float { if x < 0 { return 0.0 }; x })
}

func gelu(tensor t) tensor {
    float sqrt_2_pi = 0.7978845608028654
    elemwise_op1(t, func(float x) float {
        float inner = sqrt_2_pi * (x + 0.044715 * x * x * x)
        float ei = exp_f(2.0 * inner)
        float th = (ei - 1.0) / (ei + 1.0)
        0.5 * x * (1.0 + th)
    })
}

func softmax(tensor t, int dim) tensor {
    int d = dim
    if d < 0 { d = t.shape.ndim + d }
    tensor m = max_all(t)
    tensor shifted = sub(t, m)
    tensor e = exp_t(shifted)
    tensor s = sum_dim(e, d, true)
    div(e, s)
}

func sigmoid(tensor t) tensor {
    elemwise_op1(t, func(float x) float {
        if x > 500 { return 1.0 }
        if x < -500 { return 0.0 }
        float ep = exp_f(-x)
        1.0 / (1.0 + ep)
    })
}

func tanh_t(tensor t) tensor {
    elemwise_op1(t, func(float x) float {
        float ep = exp_f(x)
        float em = exp_f(-x)
        (ep - em) / (ep + em)
    })
}

func layer_norm(tensor t, float eps) tensor {
    if t.shape.ndim == 0 { return t }
    int last = t.shape.ndim - 1
    tensor mu = mean_dim(t, last, true)
    tensor centered = sub(t, mu)
    tensor sq = mul(centered, centered)
    tensor var = mean_dim(sq, last, true)
    tensor var_eps = add(var, scalar(eps))
    tensor std = sqrt_t(var_eps)
    div(centered, std)
}

func dropout(tensor t, float p, bool training) tensor {
    if !training || p <= 0.0 { return t }
    float scale = 1.0 / (1.0 - p)
    float[] v = new float[t.shape.size]
    int i = 0
    for i < t.shape.size {
        if _rand_float() < p { v[i] = 0.0 }
        else { v[i] = t.data[i] * scale }
        i = i + 1
    }
    tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func one_hot(int[] indices, int num_classes) tensor {
    int n = len(indices)
    float[] v = new float[n * num_classes]
    int i = 0
    for i < n * num_classes { v[i] = 0.0; i = i + 1 }
    i = 0
    for i < n {
        int cls = indices[i]
        if cls >= 0 && cls < num_classes { v[i * num_classes + cls] = 1.0 }
        i = i + 1
    }
    int[] s = new int[2]
    s[0] = n
    s[1] = num_classes
    tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func mse_loss(tensor pred, tensor target) tensor {
    tensor diff = sub(pred, target)
    tensor sq = square(diff)
    mean_all(sq)
}

func cross_entropy_loss(tensor logits, tensor targets) tensor {
    tensor probs = softmax(logits, logits.shape.ndim - 1)
    tensor log_probs = log_t(probs)
    tensor loss_term = mul(log_probs, targets)
    tensor summed = sum_all(loss_term)
    div_scalar(summed, logits.shape.dims[0] as float)
}

func l1_loss(tensor pred, tensor target) tensor {
    tensor diff = sub(pred, target)
    tensor adiff = abs_t(diff)
    mean_all(adiff)
}

func bce_logits_loss(tensor logits, tensor targets) tensor {
    tensor sig = sigmoid(logits)
    tensor loss_p = mul(targets, log_t(add(sig, scalar(1e-7))))
    tensor ones_minus_t = sub(scalar(1.0), targets)
    tensor ones_minus_sig = sub(scalar(1.0), sig)
    tensor loss_n = mul(ones_minus_t, log_t(add(ones_minus_sig, scalar(1e-7))))
    tensor total = add(loss_p, loss_n)
    neg(mean_all(total))
}

func int_to_string(int n) string {
    if n == 0 { return "0" }
    bool negative = false
    if n < 0 { negative = true; n = -n }
    string digits = ""
    for n > 0 {
        digits = string((n % 10) + 48) + digits
        n = n / 10
    }
    if negative { digits = "-" + digits }
    digits
}

func fmt_float(float val, int decimals) string {
    int ival = val as int
    float frac = val - ival as float
    if frac < 0 { frac = -frac }
    string result = int_to_string(ival)
    if decimals > 0 {
        result = result + "."
        int d = 0
        for d < decimals {
            frac = frac * 10.0
            int digit = frac as int
            result = result + int_to_string(digit)
            frac = frac - digit as float
            d = d + 1
        }
    }
    result
}

func mod_int(int a, int b) int {
    if b == 0 { return 0 }
    int r = a - (a / b) * b
    if (r > 0 && b < 0) || (r < 0 && b > 0) { r = r + b }
    r
}

func abs_f(float x) float { if x < 0 { return -x }; x }

func sqrt_f(float x) float {
    if x < 0 { return 0.0 }
    if x == 0.0 || x == 1.0 { return x }
    float g = x / 2.0
    int i = 0
    for i < 20 {
        g = (g + x / g) / 2.0
        i = i + 1
    }
    g
}

func pow_f(float base, float exp) float {
    if exp == 0 { return 1.0 }
    if base == 0 { return 0.0 }
    bool neg = exp < 0
    if neg { exp = -exp }
    float result = 1.0
    for exp >= 1.0 {
        if mod_int(exp as int, 2) == 1 { result = result * base }
        base = base * base
        exp = exp / 2.0
    }
    if neg { return 1.0 / result }
    result
}

func exp_f(float x) float {
    if x > 700 { return FLOAT_INF }
    if x < -700 { return 0.0 }
    bool neg = x < 0
    if neg { x = -x }
    float LN2_VAL = 0.6931471805599453
    int k = x / LN2_VAL as int
    float r = x - (k as float) * LN2_VAL
    float term = 1.0
    float sum = 1.0
    float ri = r
    int n = 1
    for n <= 20 {
        term = term * ri / (n as float)
        sum = sum + term
        ri = ri * r
        n = n + 1
    }
    for k > 0 { sum = sum * 2.0; k = k - 1 }
    if neg { return 1.0 / sum }
    sum
}

func log_f(float x) float {
    if x <= 0 { return FLOAT_NEG_INF }
    if x == 1.0 { return 0.0 }
    float y = 0.0
    float LN2_VAL = 0.6931471805599453
    for x >= 2.0 { x = x / 2.0; y = y + LN2_VAL }
    for x < 1.0 { x = x * 2.0; y = y - LN2_VAL }
    float guess = x - 1.0
    int i = 0
    for i < 15 {
        float eg = exp_f(guess)
        guess = guess + 2.0 * (x - eg) / (x + eg)
        i = i + 1
    }
    y + guess
}

func sin_f(float x) float {
    float PI_VAL = 3.141592653589793
    float TWO_PI = 2.0 * PI_VAL
    x = x - (x / TWO_PI as int) as float * TWO_PI
    if x > PI_VAL { x = x - TWO_PI }
    if x < -PI_VAL { x = x + TWO_PI }
    float term = x
    float sum = x
    float xx = x * x
    int n = 1
    for n <= 10 {
        float denom = 1.0
        int f_end = 2 * n + 1
        int j = 1
        for j <= f_end { denom = denom * j as float; j = j + 1 }
        term = term * (-xx) / ((2*n) as float * (2*n+1) as float)
        sum = sum + term
        n = n + 1
    }
    sum
}

func cos_f(float x) float {
    float PI_VAL = 3.141592653589793
    sin_f(x + PI_VAL / 2.0)
}

func tanh_f_func(float x) float {
    float ep = exp_f(x)
    float em = exp_f(-x)
    (ep - em) / (ep + em)
}

func reduce_idx_sum(int flat_idx, tensor_shape sh, int d) int {
    int result = 0
    int stride_before = 1
    int stride_after = 1
    int di = 0
    for di < d { stride_before = stride_before * sh.dims[di]; di = di + 1 }
    di = d + 1
    for di < sh.ndim { stride_after = stride_after * sh.dims[di]; di = di + 1 }
    result = (flat_idx / (sh.dims[d] * stride_after)) * stride_after + (flat_idx % stride_after)
    result
}

func build_reduced_shape(tensor_shape sh, int d, bool keepdim) int[] {
    int new_ndim = sh.ndim
    if !keepdim { new_ndim = new_ndim - 1 }
    int[] out = new int[new_ndim]
    int i = 0
    int j = 0
    for i < sh.ndim {
        if i == d { if keepdim { out[j] = 1; j = j + 1 } }
        else { out[j] = sh.dims[i]; j = j + 1 }
        i = i + 1
    }
    out
}

func neg(tensor t) tensor { mul_scalar(t, -1.0) }
