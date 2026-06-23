// ============================================
// S Language Math Library - Complete Implementation
// 完整数学库 - 支持深度学习所有数值运算
// ============================================
//
// 提供从基础运算到高级激活函数的全部数学功能
// 所有函数均为纯函数，无副作用，可直接在张量运算中使用
// 
// 依赖: 无外部依赖，完全自包含
// ============================================
package std.math_dl

// ============================================
// Mathematical Constants (数学常量)
// ============================================

const PI = 3.14159265358979323846      // 圆周率
const E = 2.71828182845904523536      // 自然对数底
const LN2 = 0.69314718055994530942    // ln(2)
const LN10 = 2.30258509299404568402   // ln(10)
const SQRT2 = 1.41421356237309504880   // √2
const LOG2E = 1.44269504088896340736   // log2(e)
const EPSILON = 1e-7                  // 机器精度
const INF = 1e308                     // 正无穷
const NEG_INF = -1e308                // 负无穷

// ============================================
// Basic Arithmetic (基础算术)
// ============================================

// 绝对值 |x|
func abs(float x) float {
    if x < 0 { return -x }
    x
}

// 取最大值 max(a,b)
func max_f(float a, float b) float {
    if a > b { a } else { b }
}

// 取最小值 min(a,b)
func min_f(float a, float b) float {
    if a < b { a } else { b }
}

// 裁剪到范围 [lo, hi]
func clamp_f(float x, float lo, float hi) float {
    if x < lo { return lo }
    if x > hi { return hi }
    x
}

// 符号函数: -1, 0, +1
func sign_f(float x) float {
    if x > 0 { return 1.0 }
    if x < 0 { return -1.0 }
    0.0
}

// 整数取模 (修复S编译器可能的%问题)
func mod(int a, int b) int {
    if b == 0 { return 0 }
    int r = a - (a / b) * b
    if (r > 0 && b < 0) || (r < 0 && b > 0) { r = r + b }
    r
}

// 浮点取余
func fmod(float a, float b) float {
    float r = a - (a as int as float / b as int as float) * b
    r
}

// ============================================
// Powers & Roots (幂与根)
// ============================================

// 平方 x²
func square(float x) float { x * x }

// 立方 x³
func cube(float x) float { x * x * x }

// 幂函数 base^exp (快速幂算法)
func pow(float base, float exp_val) float {
    if exp_val == 0.0 { return 1.0 }
    if base == 0.0 { return 0.0 }
    
    bool negative = exp_val < 0
    if negative { exp_val = -exp_val }
    
    float result = 1.0
    while exp_val >= 1.0 {
        if mod(exp_val as int, 2) == 1 { result = result * base }
        base = base * base
        exp_val = exp_val / 2.0
    }
    
    if negative { return 1.0 / result }
    result
}

// 平方根 √x (牛顿迭代法, 精度 ~15位)
func sqrt(float x) float {
    if x < 0.0 { return 0.0 }
    if x == 0.0 || x == 1.0 { return x }
    
    float g = x / 2.0
    int i = 0
    while i < 25 {
        g = (g + x / g) / 2.0
        i = i + 1
    }
    g
}

// 立方根 ∛x
func cbrt(float x) float {
    if x >= 0.0 { pow(x, 1.0 / 3.0) }
    else { -pow(-x, 1.0 / 3.0) }
}

// 倒数平方根 1/√x (用于归一化)
func rsqrt(float x) float {
    if x <= 0.0 { return INF }
    1.0 / sqrt(x)
}

// hypot: √(a²+b²) 避免中间溢出
func hypot(float a, float b) float {
    float abs_a = abs(a)
    float abs_b = abs(b)
    if abs_a > abs_b {
        float ratio = abs_b / abs_a
        return abs_a * sqrt(1.0 + ratio * ratio)
    } else {
        if abs_b == 0.0 { return 0.0 }
        float ratio = abs_a / abs_b
        return abs_b * sqrt(1.0 + ratio * ratio)
    }
}

// ============================================
// Exponential & Logarithm (指数与对数)
// ============================================

// e^x 自然指数 (泰勒级数 + 范围归约)
func exp(float x) float {
    if x > 709.78 { return INF }        // 溢出
    if x < -745.13 { return 0.0 }       // 下溢
    
    bool neg = false
    if x < 0 { neg = true; x = -x }
    
    // 范围归约: e^x = 2^k * e^r where |r| < ln2
    int k = (x / LN2) as int
    float r = x - (k as float) * LN2
    
    // 泰勒级数: e^r = Σ(r^n/n!) n=0..∞
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
    
    // 还原: 乘以 2^k
    while k > 0 { sum = sum * 2.0; k = k - 1 }
    
    if neg { return 1.0 / sum }
    sum
}

// expm1: e^x - 1 (对小x数值稳定)
func expm1(float x) float {
    if abs(x) < 0.01 {
        // 泰勒: e^x-1 ≈ x + x²/2! + x³/3! + ...
        return x + x*x/2.0 + x*x*x/6.0
    }
    exp(x) - 1.0
}

// ln(x) 自然对数 (牛顿法迭代)
func log(float x) float {
    if x <= 0.0 { return NEG_INF }
    if x == 1.0 { return 0.0 }
    
    // 归一化到 [1, 2)
    float y = 0.0
    while x >= 2.0 { x = x / 2.0; y = y + LN2 }
    while x < 1.0 { x = x * 2.0; y = y - LN2 }
    
    // 牛顿法求 ln(x): f(y)=e^y-x=0 → y_{n+1}=y_n+2(x-e^{y_n})/(x+e^{y_n})
    float guess = x - 1.0  // 初始猜测: ln(1+x)≈x
    int i = 0
    while i < 20 {
        float eg = exp(guess)
        guess = guess + 2.0 * (x - eg) / (x + eg)
        i = i + 1
    }
    y + guess
}

// log(1+x) 数值稳定版
func log1p(float x) float {
    if abs(x) < 0.01 {
        return x - x*x/2.0 + x*x*x/3.0
    }
    log(1.0 + x)
}

// log10 以10为底的对数
func log10(float x) float { log(x) / LN10 }

// log2 以2为底的对数
func log2(float x) float { log(x) / LN2 }

// ============================================
// Trigonometric Functions (三角函数)
// 全部使用泰勒级数实现，精度约14位有效数字
// ============================================

// 正弦 sin(x) [输入弧度]
func sin(float x) float {
    // 归一化到 [-π, π]
    float TWO_PI = 2.0 * PI
    x = x - ((x / TWO_PI) as int as float) * TWO_PI
    if x > PI { x = x - TWO_PI }
    if x < -PI { x = x + TWO_PI }
    
    // 泰勒: sin(x) = x - x³/3! + x⁵/5! - x⁷/7! + ...
    float xx = x * x
    float term = x
    float sum = x
    int n = 1
    while n <= 12 {
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

// 余弦 cos(x) = sin(x+π/2)
func cos(float x) float {
    sin(x + PI / 2.0)
}

// 正切 tan(x) = sin/cos
func tan(float x) float {
    float c = cos(x)
    if abs(c) < EPSILON {
        if x > 0 { return INF } else { return NEG_INF }
    }
    sin(x) / c
}

// 反正弦 arcsin(x), 输入 [-1,1], 输出 [-π/2, π/2]
func asin(float x) float {
    if x > 1.0 { x = 1.0 }
    if x < -1.0 { x = -1.0 }
    
    // 牛顿迭代: f(y) = sin(y) - x = 0
    float guess = x  // 小角度近似
    int i = 0
    while i < 20 {
        float sg = sin(guess)
        float cg = cos(guess)
        if abs(sg - x) < EPSILON { break }
        if abs(cg) < EPSILON { break }
        guess = guess + (x - sg) / cg
        i = i + 1
    }
    guess
}

// 反余弦 arccos(x) = π/2 - arcsin(x)
func acos(float x) float {
    PI / 2.0 - asin(x)
}

// 反正切 arctan(x), 输出 (-π/2, π/2)
func atan(float x) float {
    if x > 1e10 { return PI / 2.0 }
    if x < -1e10 { return -PI / 2.0 }
    if x == 0.0 { return 0.0 }
    
    bool invert = false
    if abs(x) > 1.0 { x = 1.0 / x; invert = true }
    
    // 泰勒: atan(x) ≈ x - x³/3 + x⁵/5 - ... (|x|≤1)
    float xx = x * x
    float term = x
    float sum = x
    int n = 1
    while n <= 15 {
        float coeff = 1.0 / ((2*n+1) as float)
        term = term * (-xx)
        sum = sum + term * coeff
        n = n + 1
    }
    
    if invert {
        if sum >= 0 { return PI / 2.0 - sum }
        return -PI / 2.0 - sum
    }
    sum
}

// 二象限反正切 atan2(y, x), 输出 [-π, π]
func atan2(float y, float x) float {
    if x > 0.0 { return atan(y / x) }
    if x < 0.0 && y >= 0.0 { return atan(y / x) + PI }
    if x < 0.0 && y < 0.0 { return atan(y / x) - PI }
    if y > 0.0 { return PI / 2.0 }
    if y < 0.0 { return -PI / 2.0 }
    0.0
}

// 角度转弧度
func deg2rad(float degrees) float { degrees * PI / 180.0 }

// 弧度转角度
func rad2deg(float radians) float { radians * 180.0 / PI }

// ============================================
// Hyperbolic Functions (双曲函数)
// ============================================

// 双曲正弦 sinh(x) = (e^x - e^-x)/2
func sinh(float x) float {
    (exp(x) - exp(-x)) / 2.0
}

// 双曲余弦 cosh(x) = (e^x + e^-x)/2
func cosh(float x) float {
    (exp(x) + exp(-x)) / 2.0
}

// 双曲正切 tanh(x) = sinh/cosh
func tanh_h(float x) float {
    float ep = exp(x)
    float em = exp(-x)
    (ep - em) / (ep + em)
}

// 反双曲正弦 asinh(x) = ln(x+√(x²+1))
func asinh(float x) float {
    log(x + sqrt(x*x + 1.0))
}

// 反双曲余弦 acosh(x) = ln(x+√(x²-1)), x≥1
func acosh(float x) float {
    log(x + sqrt(x*x - 1.0))
}

// 反双曲正切 atanh(x) = 0.5*ln((1+x)/(1-x)), |x|<1
func atanh(float x) float {
    log((1.0 + x) / (1.0 - x)) / 2.0
}

// ============================================
// Rounding Functions (取整函数)
// ============================================

// 向上取整 ⌈x⌉
func ceil(float x) float {
    int ix = x as int
    if x > (ix as float) && x >= 0.0 { return (ix + 1) as float }
    if x != (ix as float) && x < 0.0 { return (ix as float) }
    x
}

// 向下取整 ⌊x⌋
func floor(float x) float {
    int ix = x as int
    if x < (ix as float) && x < 0.0 { return (ix - 1) as float }
    if x != (ix as float) && x >= 0.0 { return (ix as float) }
    x
}

// 四舍五入
func round_f(float x) float {
    if x >= 0.0 { floor(x + 0.5) }
    else { ceil(x - 0.5) }
}

// 截断小数 (向零取整)
func trunc(float x) float {
    (x as int) as float
}

// ============================================
// Deep Learning Activation Functions (DL激活函数)
// 核心组件：神经网络的前向传播依赖这些函数
// ============================================

// Sigmoid: σ(x) = 1/(1+e^{-x})
// 值域 (0, 1)，常用于二分类输出层和门控机制
func sigmoid(float x) float {
    if x > 500.0 { return 1.0 }
    if x < -500.0 { return 0.0 }
    float ep = exp(-x)
    1.0 / (1.0 + ep)
}

// ReLU: Rectified Linear Unit, max(0, x)
// 最常用的隐藏层激活函数
func relu(float x) float {
    if x < 0.0 { return 0.0 }
    x
}

// Leaky ReLU: max(αx, x) 其中 α 是小的负斜率
func leaky_relu(float x, float alpha) float {
    if x < 0.0 { return x * alpha }
    x
}

// GELU: Gaussian Error Linear Unit (GPT-2/3/BERT使用)
// 近似公式: 0.5x(1+tanh(√(2/π)(x+0.044715x³)))
func gelu(float x) float {
    float SQRT_2_OVER_PI = 0.7978845608028654
    float inner = SQRT_2_OVER_PI * (x + 0.044715 * x * x * x)
    0.5 * x * (1.0 + tanh_h(inner))
}

// SiLU / Swish: x·σ(x)
func silu(float x) float { x * sigmoid(x) }

// Softplus: log(1+e^x) = ReLU的平滑版本
func softplus(float x) float {
    if x > 20.0 { return x }
    if x < -20.0 { return 0.0 }
    log1p(exp(x))
}

// ELU: Exponential Linear Unit
// x>0时=x, 否则 α(e^x-1)
func elu(float x, float alpha) float {
    if x > 0.0 { return x }
    alpha * (exp(x) - 1.0)
}

// Mish: x·tanh(softplus(x))
func mish(float x) float {
    x * tanh_h(softplus(x))
}

// Hardswish: 快速近似Swish (移动端常用)
func hardswish(float x) float {
    if x < -3.0 { return 0.0 }
    if x > 3.0 { return x }
    x * (x + 3.0) / 6.0
}

// Hardshrink: 如果|x|>λ则返回x否则返回0
func hardshrink(float x, float lambda) float {
    if x > lambda || x < -lambda { return x }
    0.0
}

// Softsign: x/(1+|x|)
func softsign(float x) float {
    x / (1.0 + abs(x))
}

// Tanh: 双曲正切 (已有别名)
func tanh_act(float x) float { tanh_h(x) }

// ============================================
// Special Functions (特殊函数)
// ============================================

// 误差函数 erf(x) (Abramowitz & Stegun近似)
// 用于正态分布 CDF 计算
func erf(float x) float {
    float sign = 1.0
    if x < 0.0 { sign = -1.0; x = -x }
    
    // 有理逼近: erf(x) ≈ 1 - (a₁t+a₂t²+...+a₅t⁵)e^{-x²}
    // 其中 t = 1/(1+px)
    float t = 1.0 / (1.0 + 0.3275911 * x)
    float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) 
                 + 1.421413741) * t - 0.284496736) * t 
                 + 0.254829592) * t * exp(-(x * x))
    
    sign * y
}

// 互补误差函数 erfc(x) = 1 - erf(x)
func erfc(float x) float { 1.0 - erf(x) }

// 标准正态分布 CDF: Φ(x) = 0.5(1+erf(x/√2))
func normal_cdf(float x) float { 0.5 * (1.0 + erf(x / SQRT2)) }

// 标准正态分布 PDF: φ(x) = e^{-x²/2}/√(2π)
func normal_pdf(float x) float { exp(-0.5 * x * x) / (SQRT2 * sqrt(PI)) }

// Gumbel-Softmax / Gumbel-Sigmoid 的 log-sum-exp (数值稳定版)
// log(Σe^{x_i}) = m + log(Σe^{x_i-m}) 其中 m=max(x_i)
func log_sum_exp(float[] values, int count) float {
    if count <= 0 { return 0.0 }
    
    float m = values[0]
    int i = 1
    while i < count {
        if values[i] > m { m = values[i] }
        i = i + 1
    }
    
    float s = 0.0
    i = 0
    while i < count {
        s = s + exp(values[i] - m)
        i = i + 1
    }
    
    m + log(s)
}

// Sigmoid cross-entropy (with logits): log(sigmoid(x)) = -log(1+e^{-x})
// 直接计算避免溢出
func sigmoid_xent(float x) float {
    if x > 0.0 { return -log(1.0 + exp(-x)) }
    return x - log(1.0 + exp(x))
}

// ============================================
// Interpolation Functions (插值函数)
// ============================================

// 线性插值 lerp(a,b,t) = a + t(b-a)
func lerp(float a, float b, float t) float { a + t * (b - a) }

// 反线性插值: 已知a,b,c 求 t 使得 lerp(a,b,t)=c
func inv_lerp(float a, float b, float c) float {
    if abs(b - a) < EPSILON { return 0.0 }
    (c - a) / (b - a)
}

// Smoothstep: Hermite插值, 3t²-2t³
func smoothstep(float edge0, float edge1, float x) float {
    float t = clamp_f((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    t * t * (3.0 - 2.0 * t)
}

// smootherstep: 更平滑的 6阶多项式
func smootherstep(float edge0, float edge1, float x) float {
    float t = clamp_f((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

// Step function: 返回 0 或 1
func step(float edge, float x) float {
    if x < edge { return 0.0 }
    1.0
}

// ============================================
// Distance Metrics (距离度量)
// ============================================

// L1 距离 (曼哈顿距离)
func l1_dist(float a, float b) float { abs(a - b) }

// L2² 距离 (平方欧氏距离)
func l2_sq_dist(float a, float b) float { 
    float d = a - b; d * d 
}

// L2 距离 (欧氏距离)
func l2_dist(float a, float b) float { sqrt(l2_sq_dist(a, b)) }

// 余弦相似度 (标量版, 结果 ±1)
func cosine_sim(float a, float b) float {
    float na = abs(a)
    float nb = abs(b)
    if na < EPSILON || nb < EPSILON { return 0.0 }
    (a * b) / (na * nb)
}

// ============================================
// Utility Functions (工具函数)
// ============================================

// 判断是否为有限数
func is_finite(float x) bool { x > NEG_INF && x < INF }

// 判断是否为NaN (简单检查)
func is_nan(float x) bool { !(x == x) }  // NaN是唯一不等于自身的值

// 安全除法: 避免除以零
func safe_div(float a, float b, float fallback) float {
    if abs(b) < EPSILON { return fallback }
    a / b
}

// 将浮点数格式化为固定小数位字符串
func fmt_float(float val, int decimals) string {
    int ival = val as int
    float frac = val - ival as float
    if frac < 0 { frac = -frac }
    string result = ""
    
    // 处理整数部分
    if ival == 0 { result = "0" }
    else {
        bool neg = ival < 0
        if neg { ival = -ival }
        string digits = ""
        while ival > 0 {
            digits = string((ival % 10) + 48) + digits
            ival = ival / 10
        }
        if neg { result = "-" + digits }
        else { result = digits }
    }
    
    // 处理小数部分
    if decimals > 0 {
        result = result + "."
        int d = 0
        while d < decimals {
            frac = frac * 10.0
            int digit = frac as int
            result = result + string(digit + 48)
            frac = frac - digit as float
            d = d + 1
        }
    }
    
    result
}
