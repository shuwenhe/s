package std.tensor_core

const FLOAT_EPSILON = 1e-7
const FLOAT_INF = 1e308
const FLOAT_NEG_INF = -1e308

struct TensorShape {
    int[] dims
    int ndim
    int size
}

struct Tensor {
    TensorShape shape
    float[] data
    string device
    bool requires_grad
}

func make_shape(int[] dims) TensorShape {
    int ndim = len(dims)
    int total_size = 1
    int i = 0
    while i < ndim {
        total_size = total_size * dims[i]
        i = i + 1
    }
    TensorShape { dims: dims, ndim: ndim, size: total_size }
}

func numel(Tensor t) int { t.shape.size }

func ndim(Tensor t) int { t.shape.ndim }

func dim_size(Tensor t, int axis) int {
    if axis < 0 { axis = t.shape.ndim + axis }
    if axis >= 0 && axis < t.shape.ndim { return t.shape.dims[axis] }
    return 1
}

func shape_str(TensorShape s) string {
    string result = "("
    int i = 0
    while i < s.ndim {
        if i > 0 { result = result + ", " }
        result = result + int_to_string(s.dims[i])
        i = i + 1
    }
    result = result + ")"
    result
}

func same_shape(Tensor a, Tensor b) bool {
    if a.shape.ndim != b.shape.ndim { return false }
    int i = 0
    while i < a.shape.ndim {
        if a.shape.dims[i] != b.shape.dims[i] { return false }
        i = i + 1
    }
    return true
}

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

func make_tensor(float[] values, int[] shape_dims) Tensor {
    TensorShape sh = make_shape(shape_dims)
    int val_count = len(values)
    if val_count < sh.size {
        float[] padded = new float[sh.size]
        int i = 0
        while i < val_count { padded[i] = values[i]; i = i + 1 }
        while i < sh.size { padded[i] = 0.0; i = i + 1 }
        values = padded
    }
    Tensor { shape: sh, data: values, device: "cpu", requires_grad: false }
}

func zeros(int[] shape_dims) Tensor {
    TensorShape sh = make_shape(shape_dims)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size { vals[i] = 0.0; i = i + 1 }
    Tensor { shape: sh, data: vals, device: "cpu", requires_grad: false }
}

func ones(int[] shape_dims) Tensor {
    TensorShape sh = make_shape(shape_dims)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size { vals[i] = 1.0; i = i + 1 }
    Tensor { shape: sh, data: vals, device: "cpu", requires_grad: false }
}

func full(int[] shape_dims, float fill_value) Tensor {
    TensorShape sh = make_shape(shape_dims)
    float[] vals = new float[sh.size]
    int i = 0
    while i < sh.size { vals[i] = fill_value; i = i + 1 }
    Tensor { shape: sh, data: vals, device: "cpu", requires_grad: false }
}

func scalar(float value) Tensor {
    float[] v = new float[1]
    v[0] = value
    int[] s = new int[1]
    s[0] = 1
    Tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func arange(int start, int stop, int step) Tensor {
    int count = (stop - start) / step
    if count <= 0 { count = 1 }
    float[] v = new float[count]
    int i = 0
    int val = start
    while i < count {
        v[i] = val as float
        val = val + step
        i = i + 1
    }
    int[] s = new int[1]
    s[0] = count
    Tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func linspace(float start, float stop, int n) Tensor {
    float[] v = new float[n]
    float delta = 0.0
    if n > 1 { delta = (stop - start) / ((n-1) as float) }
    int i = 0
    while i < n {
        v[i] = start + (i as float) * delta
        i = i + 1
    }
    int[] s = new int[1]
    s[0] = n
    Tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func eye(int n) Tensor {
    int[] shape = new int[2]
    shape[0] = n
    shape[1] = n
    TensorShape sh = make_shape(shape)
    float[] v = new float[sh.size]

    int r = 0
    while r < n {
        int c = 0
        while c < n {
            if r == c { v[r * n + c] = 1.0 }
            else { v[r * n + c] = 0.0 }
            c = c + 1
        }
        r = r + 1
    }
    Tensor { shape: sh, data: v, device: "cpu", requires_grad: false }
}

func zeros_like(Tensor t) Tensor { zeros(t.shape.dims) }

func ones_like(Tensor t) Tensor { ones(t.shape.dims) }

var _rand_seed = 42

func set_seed(int seed) void { _rand_seed = seed }

func _rand_float() float {
    _rand_seed = _rand_seed * 1103515245 + 12345
    float r = (_rand_seed & 0x7fffffff) as float / 2147483647.0
    r
}

func rand(int[] shape_dims) Tensor {
    TensorShape sh = make_shape(shape_dims)
    float[] v = new float[sh.size]
    int i = 0
    while i < sh.size { v[i] = _rand_float(); i = i + 1 }
    Tensor { shape: sh, data: v, device: "cpu", requires_grad: false }
}

func randn(int[] shape_dims, float mean, float std) Tensor {
    TensorShape sh = make_shape(shape_dims)
    float[] v = new float[sh.size]
    int i = 0
    while i < sh.size {
        float u1 = _rand_float()
        float u2 = _rand_float()
        if u1 < 1e-10 { u1 = 1e-10 }
        float z = sqrt(-2.0 * log(u1)) * cos(6.283185307179586 * u2)
        v[i] = mean + z * std
        i = i + 1
    }
    Tensor { shape: sh, data: v, device: "cpu", requires_grad: false }
}

func xavier_uniform(int fan_in, int fan_out) Tensor {
    int[] shape = new int[2]
    shape[0] = fan_in
    shape[1] = fan_out
    float limit = sqrt(6.0 / ((fan_in as float) + (fan_out as float)))
    Tensor t = rand(shape)
    int i = 0
    while i < t.shape.size {
        t.data[i] = (t.data[i] * 2.0 - 1.0) * limit
        i = i + 1
    }
    t
}

func kaiming_normal(int fan_in, int fan_out) Tensor {
    int[] shape = new int[2]
    shape[0] = fan_in
    shape[1] = fan_out
    float std_val = sqrt(2.0 / fan_in as float)
    randn(shape, 0.0, std_val)
}

func item(Tensor t) float {
    t.data[0]
}

func get(Tensor t, int[] indices) float {
    int idx = flat_index(t.shape, indices)
    t.data[idx]
}

func get_flat(Tensor t, int idx) float {
    t.data[idx]
}

func set_flat(Tensor mut t, int idx, float value) void {
    t.data[idx] = value
}

func print_tensor_info(Tensor t) void {
    print("Tensor" + shape_str(t.shape) + " device=" + t.device)
}

func print_values(Tensor t, int n) void {
    print_tensor_info(t)
    int limit = n
    if limit > t.shape.size { limit = t.shape.size }
    string s = "["
    int i = 0
    while i < limit {
        if i > 0 { s = s + ", " }
        s = s + fmt_float(t.data[i], 4)
        i = i + 1
    }
    if limit < t.shape.size { s = s + ", ..." }
    s = s + "]"
    println(s)
}

func reshape(Tensor t, int[] new_dims) Tensor {
    TensorShape new_sh = make_shape(new_dims)
    if new_sh.size != t.shape.size {
        return t
    }
    Tensor { shape: new_sh, data: t.data, device: t.device, requires_grad: t.requires_grad }
}

func flatten(Tensor t) Tensor {
    int[] flat_s = new int[1]
    flat_s[0] = t.shape.size
    reshape(t, flat_s)
}

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

func unsqueeze(Tensor t, int dim_pos) Tensor {
    int new_ndim = t.shape.ndim + 1
    int[] new_dims = new int[new_ndim]
    int i = 0
    int j = 0
    while i < new_ndim {
        if i == dim_pos { new_dims[i] = 1 }
        else {
            new_dims[i] = t.shape.dims[j]
            j = j + 1
        }
        i = i + 1
    }
    reshape(t, new_dims)
}

func transpose_2d(Tensor t) Tensor {
    if t.shape.ndim != 2 { return t }
    int rows = t.shape.dims[0]
    int cols = t.shape.dims[1]

    float[] v = new float[t.shape.size]
    int r = 0
    while r < rows {
        int c = 0
        while c < cols {
            v[c * rows + r] = t.data[r * cols + c]
            c = c + 1
        }
        r = r + 1
    }

    int[] new_s = new int[2]
    new_s[0] = cols
    new_s[1] = rows
    Tensor { shape: make_shape(new_s), data: v, device: t.device, requires_grad: t.requires_grad }
}

func transpose(Tensor t, int dim0, int dim1) Tensor {
    if t.shape.ndim == 2 { return transpose_2d(t) }
    int[] new_dims = new int[t.shape.ndim]
    int i = 0
    while i < t.shape.ndim {
        if i == dim0 { new_dims[i] = t.shape.dims[dim1] }
        else if i == dim1 { new_dims[i] = t.shape.dims[dim0] }
        else { new_dims[i] = t.shape.dims[i] }
        i = i + 1
    }
    Tensor { shape: make_shape(new_dims), data: t.data, device: t.device, requires_grad: t.requires_grad }
}

func view(Tensor t, int[] new_dims) Tensor {
    reshape(t, new_dims)
}

func contiguous(Tensor t) Tensor { t }

func add(Tensor a, Tensor b) Tensor {
    if same_shape(a, b) {
        return elemwise_op2(a, b, func(float x, float y) float { x + y })
    }
    if is_scalar(b) { return add_scalar(a, item(b)) }
    if is_scalar(a) { return add_scalar(b, item(a)) }
    a
}

func add_scalar(Tensor t, float s) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { v[i] = t.data[i] + s; i = i + 1 }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func sub(Tensor a, Tensor b) Tensor {
    if is_scalar(b) { return add_scalar(a, -item(b)) }
    if same_shape(a, b) { return elemwise_op2(a, b, func(float x, float y) float { x - y }) }
    if is_scalar(a) { return neg(add_scalar(b, -item(a))) }
    a
}

func mul(Tensor a, Tensor b) Tensor {
    if is_scalar(b) { return mul_scalar(a, item(b)) }
    if is_scalar(a) { return mul_scalar(b, item(a)) }
    if same_shape(a, b) { return elemwise_op2(a, b, func(float x, float y) float { x * y }) }
    a
}

func mul_scalar(Tensor t, float s) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { v[i] = t.data[i] * s; i = i + 1 }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func div(Tensor a, Tensor b) Tensor {
    if is_scalar(b) { return div_scalar(a, item(b)) }
    if same_shape(a, b) {
        return elemwise_op2(a, b, func(float x, float y) float { 
            if abs(y) < FLOAT_EPSILON { return 0.0 }
            x / y 
        })
    }
    a
}

func div_scalar(Tensor t, float s) Tensor {
    if abs(s) < FLOAT_EPSILON { return t }
    mul_scalar(t, 1.0 / s)
}

func neg(Tensor t) Tensor { mul_scalar(t, -1.0) }

func pow_t(Tensor t, float exp) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { v[i] = pow_f(t.data[i], exp); i = i + 1 }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func square(Tensor t) Tensor { pow_t(t, 2.0) }

func sqrt_t(Tensor t) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { 
        if t.data[i] >= 0 { v[i] = sqrt_f(t.data[i]) }
        else { v[i] = 0.0 }
        i = i + 1
    }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func exp_t(Tensor t) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { v[i] = exp_f(t.data[i]); i = i + 1 }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func log_t(Tensor t) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { 
        if t.data[i] > 0 { v[i] = log_f(t.data[i]) }
        else { v[i] = FLOAT_NEG_INF }
        i = i + 1
    }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func abs_t(Tensor t) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size { v[i] = abs_f(t.data[i]); i = i + 1 }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func clamp_t(Tensor t, float lo, float hi) Tensor {
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        float x = t.data[i]
        if x < lo { x = lo }
        if x > hi { x = hi }
        v[i] = x
        i = i + 1
    }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func is_scalar(Tensor t) bool { t.shape.size == 1 }

func elemwise_op2(Tensor a, Tensor b, func(float, float) float op) Tensor {
    int n = a.shape.size
    float[] v = new float[n]
    int i = 0
    while i < n { v[i] = op(a.data[i], b.data[i]); i = i + 1 }
    Tensor { shape: a.shape, data: v, device: "cpu", requires_grad: false }
}

func elemwise_op1(Tensor t, func(float) float op) Tensor {
    int n = t.shape.size
    float[] v = new float[n]
    int i = 0
    while i < n { v[i] = op(t.data[i]); i = i + 1 }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func sum_all(Tensor t) Tensor {
    float s = 0.0
    int i = 0
    while i < t.shape.size { s = s + t.data[i]; i = i + 1 }
    scalar(s)
}

func sum_dim(Tensor t, int target_dim, bool keepdim) Tensor {
    if t.shape.ndim == 0 { return sum_all(t) }
    int d = target_dim
    if d < 0 { d = t.shape.ndim + d }
    if d < 0 || d >= t.shape.ndim { return sum_all(t) }

    int d_size = t.shape.dims[d]
    int out_n = t.shape.size / d_size
    float[] sums = new float[out_n]
    int i = 0
    while i < out_n { sums[i] = 0.0; i = i + 1 }

    i = 0
    while i < t.shape.size {
        int oi = reduce_idx_sum(i, t.shape, d)
        sums[oi] = sums[oi] + t.data[i]
        i = i + 1
    }

    int new_ndim = t.shape.ndim
    if !keepdim { new_ndim = new_ndim - 1 }
    int[] out_d = build_reduced_shape(t.shape, d, keepdim)

    Tensor { shape: make_shape(out_d), data: sums, device: "cpu", requires_grad: false }
}

func mean_all(Tensor t) Tensor {
    float s = item(sum_all(t))
    scalar(s / t.shape.size as float)
}

func mean_dim(Tensor t, int dim, bool keepdim) Tensor {
    if t.shape.ndim == 0 { return mean_all(t) }
    int d = dim
    if d < 0 { d = t.shape.ndim + d }
    int d_size = t.shape.dims[d]
    Tensor s = sum_dim(t, d, keepdim)
    div_scalar(s, d_size as float)
}

func max_all(Tensor t) Tensor {
    if t.shape.size == 0 { return scalar(FLOAT_NEG_INF) }
    float m = t.data[0]
    int i = 1
    while i < t.shape.size {
        if t.data[i] > m { m = t.data[i] }
        i = i + 1
    }
    scalar(m)
}

func min_all(Tensor t) Tensor {
    if t.shape.size == 0 { return scalar(FLOAT_INF) }
    float m = t.data[0]
    int i = 1
    while i < t.shape.size {
        if t.data[i] < m { m = t.data[i] }
        i = i + 1
    }
    scalar(m)
}

func norm(Tensor t) Tensor {
    float s = 0.0
    int i = 0
    while i < t.shape.size { s = s + t.data[i] * t.data[i]; i = i + 1 }
    scalar(sqrt_f(s))
}

func matmul(Tensor a, Tensor b) Tensor {
    if a.shape.ndim != 2 || b.shape.ndim != 2 { return a }

    int M = a.shape.dims[0]
    int K = a.shape.dims[1]
    int K2 = b.shape.dims[0]
    int N = b.shape.dims[1]

    if K != K2 { return a }

    float[] v = new float[M * N]
    int m = 0
    while m < M {
        int n = 0
        while n < N {
            float s = 0.0
            int k = 0
            while k < K {
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
    Tensor { shape: make_shape(out_s), data: v, device: "cpu", requires_grad: false }
}

func dot(Tensor a, Tensor b) Tensor {
    if a.shape.ndim != 1 || b.shape.ndim != 1 { return scalar(0.0) }
    int n = a.shape.dims[0]
    if n != b.shape.dims[0] { return scalar(0.0) }
    float s = 0.0
    int i = 0
    while i < n { s = s + a.data[i] * b.data[i]; i = i + 1 }
    scalar(s)
}

func outer(Tensor a, Tensor b) Tensor {
    int m = a.shape.dims[0]
    int n = b.shape.dims[0]
    float[] v = new float[m * n]
    int i = 0
    while i < m {
        int j = 0
        while j < n {
            v[i * n + j] = a.data[i] * b.data[j]
            j = j + 1
        }
        i = i + 1
    }
    int[] s = new int[2]
    s[0] = m
    s[1] = n
    Tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func cat(Tensor[] tensors, int axis) Tensor {
    if len(tensors) == 0 { return zeros({0}) }
    if len(tensors) == 1 { return tensors[0] }

    int d = axis
    if d < 0 { d = tensors[0].shape.ndim + d }

    int concat_total = 0
    int ti = 0
    while ti < len(tensors) { 
        concat_total = concat_total + tensors[ti].shape.dims[d]
        ti = ti + 1 
    }

    int[] out_d = new int[tensors[0].shape.ndim]
    int i = 0
    while i < tensors[0].shape.ndim {
        if i == d { out_d[i] = concat_total }
        else { out_d[i] = tensors[0].shape.dims[i] }
        i = i + 1
    }

    int total_sz = make_shape(out_d).size
    float[] v = new float[total_sz]
    int offset = 0
    ti = 0
    while ti < len(tensors) {
        int sz = tensors[ti].shape.size
        int j = 0
        while j < sz { v[offset + j] = tensors[ti].data[j]; j = j + 1 }
        offset = offset + sz
        ti = ti + 1
    }
    Tensor { shape: make_shape(out_d), data: v, device: "cpu", requires_grad: false }
}

func relu(Tensor t) Tensor {
    elemwise_op1(t, func(float x) float { if x < 0 { return 0.0 }; x })
}

func gelu(Tensor t) Tensor {
    float sqrt_2_pi = 0.7978845608028654
    elemwise_op1(t, func(float x) float {
        float inner = sqrt_2_pi * (x + 0.044715 * x * x * x)
        float ei = exp_f(2.0 * inner)
        float th = (ei - 1.0) / (ei + 1.0)
        0.5 * x * (1.0 + th)
    })
}

func softmax(Tensor t, int dim) Tensor {
    int d = dim
    if d < 0 { d = t.shape.ndim + d }

    Tensor m = max_all(t)
    Tensor shifted = sub(t, m)
    Tensor e = exp_t(shifted)

    Tensor s = sum_dim(e, d, true)
    div(e, s)
}

func sigmoid(Tensor t) Tensor {
    elemwise_op1(t, func(float x) float {
        if x > 500 { return 1.0 }
        if x < -500 { return 0.0 }
        float ep = exp_f(-x)
        1.0 / (1.0 + ep)
    })
}

func tanh_t(Tensor t) Tensor {
    elemwise_op1(t, func(float x) float {
        float ep = exp_f(x)
        float em = exp_f(-x)
        (ep - em) / (ep + em)
    })
}

func layer_norm(Tensor t, float eps) Tensor {
    if t.shape.ndim == 0 { return t }
    int last = t.shape.ndim - 1

    Tensor mu = mean_dim(t, last, true)
    Tensor centered = sub(t, mu)
    Tensor sq = mul(centered, centered)
    Tensor var = mean_dim(sq, last, true)
    Tensor var_eps = add(var, scalar(eps))
    Tensor std = sqrt_t(var_eps)
    div(centered, std)
}

func dropout(Tensor t, float p, bool training) Tensor {
    if !training || p <= 0.0 { return t }
    float scale = 1.0 / (1.0 - p)
    float[] v = new float[t.shape.size]
    int i = 0
    while i < t.shape.size {
        if _rand_float() < p { v[i] = 0.0 }
        else { v[i] = t.data[i] * scale }
        i = i + 1
    }
    Tensor { shape: t.shape, data: v, device: "cpu", requires_grad: false }
}

func one_hot(int[] indices, int num_classes) Tensor {
    int n = len(indices)
    float[] v = new float[n * num_classes]
    int i = 0
    while i < n * num_classes { v[i] = 0.0; i = i + 1 }
    i = 0
    while i < n {
        int cls = indices[i]
        if cls >= 0 && cls < num_classes { v[i * num_classes + cls] = 1.0 }
        i = i + 1
    }
    int[] s = new int[2]
    s[0] = n
    s[1] = num_classes
    Tensor { shape: make_shape(s), data: v, device: "cpu", requires_grad: false }
}

func mse_loss(Tensor pred, Tensor target) Tensor {
    Tensor diff = sub(pred, target)
    Tensor sq = square(diff)
    mean_all(sq)
}

func cross_entropy_loss(Tensor logits, Tensor targets) Tensor {
    Tensor probs = softmax(logits, logits.shape.ndim - 1)
    Tensor log_probs = log_t(probs)
    Tensor loss_term = mul(log_probs, targets)
    Tensor summed = sum_all(loss_term)
    div_scalar(summed, logits.shape.dims[0] as float)
}

func l1_loss(Tensor pred, Tensor target) Tensor {
    Tensor diff = sub(pred, target)
    Tensor adiff = abs_t(diff)
    mean_all(adiff)
}

func bce_logits_loss(Tensor logits, Tensor targets) Tensor {
    Tensor sig = sigmoid(logits)
    Tensor loss_p = mul(targets, log_t(add(sig, scalar(1e-7))))
    Tensor ones_minus_t = sub(scalar(1.0), targets)
    Tensor ones_minus_sig = sub(scalar(1.0), sig)
    Tensor loss_n = mul(ones_minus_t, log_t(add(ones_minus_sig, scalar(1e-7))))
    Tensor total = add(loss_p, loss_n)
    neg(mean_all(total))
}

func int_to_string(int n) string {
    if n == 0 { return "0" }
    bool negative = false
    if n < 0 { negative = true; n = -n }
    string digits = ""
    while n > 0 {
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
        while d < decimals {
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
    while i < 20 {
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
    while exp >= 1.0 {
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
    while n <= 20 {
        term = term * ri / (n as float)
        sum = sum + term
        ri = ri * r
        n = n + 1
    }
    while k > 0 { sum = sum * 2.0; k = k - 1 }
    if neg { return 1.0 / sum }
    sum
}

func log_f(float x) float {
    if x <= 0 { return FLOAT_NEG_INF }
    if x == 1.0 { return 0.0 }
    float y = 0.0
    float LN2_VAL = 0.6931471805599453
    while x >= 2.0 { x = x / 2.0; y = y + LN2_VAL }
    while x < 1.0 { x = x * 2.0; y = y - LN2_VAL }
    float guess = x - 1.0
    int i = 0
    while i < 15 {
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
    while n <= 10 {
        float denom = 1.0
        int f_end = 2 * n + 1
        int j = 1
        while j <= f_end { denom = denom * j as float; j = j + 1 }
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

func reduce_idx_sum(int flat_idx, TensorShape sh, int d) int {
    int result = 0
    int stride_before = 1
    int stride_after = 1
    int di = 0
    while di < d { stride_before = stride_before * sh.dims[di]; di = di + 1 }
    di = d + 1
    while di < sh.ndim { stride_after = stride_after * sh.dims[di]; di = di + 1 }
    result = (flat_idx / (sh.dims[d] * stride_after)) * stride_after + (flat_idx % stride_after)
    result
}

func build_reduced_shape(TensorShape sh, int d, bool keepdim) int[] {
    int new_ndim = sh.ndim
    if !keepdim { new_ndim = new_ndim - 1 }
    int[] out = new int[new_ndim]
    int i = 0
    int j = 0
    while i < sh.ndim {
        if i == d { if keepdim { out[j] = 1; j = j + 1 } }
        else { out[j] = sh.dims[i]; j = j + 1 }
        i = i + 1
    }
    out
}

func neg(Tensor t) Tensor { mul_scalar(t, -1.0) }
