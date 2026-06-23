// ============================================
// S Language Standard Math Library (Enhanced for Deep Learning)
// 标准数学库 - 增强版（支持深度学习）
// ============================================
package std.math

// ============================================
// Constants (常量)
// ============================================

const PI = 3.14159265358979323846
const E = 2.71828182845904523536
const LN2 = 0.69314718055994530942
const LN10 = 2.30258509299404568402
const SQRT2 = 1.41421356237309504880
const EPSILON = 1e-7
const INF = 1e308
const NEG_INF = -1e308

// ============================================
// Basic Operations (基础运算)
// ============================================

// Absolute value
func abs(float x) float {
    if x < 0 { return -x }
    x
}

// Maximum
func max(float a, float b) float {
    if a > b { a } else { b }
}

// Minimum  
func min(float a, float b) float {
    if a < b { a } else { b }
}

// Clamp value to range
func clamp(float x, float lo, float hi) float {
    if x < lo { return lo }
    if x > hi { return hi }
    x
}

// Sign function: returns -1, 0, or 1
func sign(float x) float {
    if x > 0 { return 1.0 }
    if x < 0 { return -1.0 }
    0.0
}

// Integer versions
func iabs(int x) int {
    if x < 0 { return -x }
    x
}

func imax(int a, int b) int {
    if a > b { a } else { b }
}

func imin(int a, int b) int {
    if a < b { a } else { b }
}

// Modulo operation (fixes S language % limitation)
func mod(int a, int b) int {
    if b == 0 { return 0 }
    int r = a - (a / b) * b
    // Ensure result has same sign as divisor
    if (r > 0 && b < 0) || (r < 0 && b > 0) { r = r + b }
    r
}

func fmod(float a, float b) float {
    float r = a - (a as int) / (b as int) * b
    r
}

// Power function: base^exp
func pow(float base, float exp) float {
    if exp == 0 { return 1.0 }
    if base == 0 { return 0.0 }
    
    bool negative = exp < 0
    if negative { exp = -exp }
    
    float result = 1.0
    while exp >= 1 {
        if mod(exp as int, 2) == 1 {
            result = result * base
        }
        base = base * base
        exp = exp / 2
    }
    
    if negative { return 1.0 / result }
    result
}

// Square root (Newton's method)
func sqrt(float x) float {
    if x < 0 { return 0.0 }
    if x == 0 || x == 1 { return x }
    
    float guess = x / 2.0
    int i = 0
    while i < 20 {
        guess = (guess + x / guess) / 2.0
        i = i + 1
    }
    guess
}

// Cube root
func cbrt(float x) float {
    if x >= 0 { return pow(x, 1.0 / 3.0) }
    return -pow(-x, 1.0 / 3.0)
}

// ============================================
// Exponential & Logarithmic (指数与对数)
// ============================================

// e^x using Taylor series
func exp(float x) float {
    // Handle large values
    if x > 700 { return INF }
    if x < -700 { return 0.0 }
    
    // e^x = e^(x*ln(2)/ln(2)) = 2^(x/ln(2))
    // Use Taylor series for small values
    bool negative = false
    if x < 0 {
        negative = true
        x = -x
    }
    
    // Reduce: e^x = e^(k*ln2 + r) = 2^k * e^r where |r| < ln2
    int k = x / LN2
    float r = x - (k as float) * LN2
    
    // Taylor series: e^r = 1 + r + r^2/2! + r^3/3! + ...
    float term = 1.0
    float sum = 1.0
    float rn = 1.0
    int n = 1
    while n <= 20 {
        rn = rn * r
        term = term * n  // factorial grows in denominator... 
                         // Actually: term_n = r^n / n!
        // Recompute properly
        n = n + 1
    }
    
    // Simpler approach: direct Taylor
    sum = 1.0 + r
    float ri = r
    float fi = 1.0
    int j = 2
    while j <= 15 {
        ri = ri * r
        fi = fi * j
        sum = sum + ri / fi
        j = j + 1
    }
    
    // Multiply by 2^k
    while k > 0 {
        sum = sum * 2.0
        k = k - 1
    }
    
    if negative { return 1.0 / sum }
    sum
}

// Natural logarithm using Newton's method
func log(float x) float {
    if x <= 0 { return NEG_INF }
    if x == 1 { return 0.0 }
    
    // Initial guess using bit manipulation approximation
    // For simplicity, use iterative method
    float y = 0.0
    
    // Normalize to [1, 2)
    while x >= 2.0 {
        x = x / 2.0
        y = y + LN2
    }
    while x < 1.0 {
        x = x * 2.0
        y = y - LN2
    }
    
    // Newton's method for ln(x): y_{n+1} = y_n + 2*(x - e^{y_n})/(x + e^{y_n})
    float guess = x - 1.0  // ln(1+x) ≈ x for small x
    int i = 0
    while i < 15 {
        float eg = exp(guess)
        guess = guess + 2.0 * (x - eg) / (x + eg)
        i = i + 1
    }
    
    y + guess
}

// Log base 10
func log10(float x) float {
    log(x) / LN10
}

// Log base 2
func log2(float x) float {
    log(x) / LN2
}

// Logarithm of 1+x (numerically stable for small x)
func log1p(float x) float {
    if abs(x) < 0.01 {
        // Taylor: log(1+x) ≈ x - x²/2 + x³/3 - ...
        return x - x*x/2.0 + x*x*x/3.0
    }
    log(1.0 + x)
}

// ============================================
// Trigonometric Functions (三角函数)
// ============================================

// Sine function using Taylor series
func sin(float x) float {
    // Normalize to [-π, π]
    x = fmod(x, 2.0 * PI)
    if x > PI { x = x - 2.0 * PI }
    if x < -PI { x = x + 2.0 * PI }
    
    // Taylor series: sin(x) = x - x³/3! + x⁵/5! - x⁷/7! + ...
    float term = x
    float sum = x
    float xx = x * x
    int i = 1
    while i <= 10 {
        float denom = 1.0
        int j = 1
        int fact_end = 2 * i + 1
        while j <= fact_end {
            denom = denom * j
            j = j + 1
        }
        term = term * (-xx) / ((2*i) * (2*i+1))
        sum = sum + term
        i = i + 1
    }
    sum
}

// Cosine function
func cos(float x) float {
    sin(x + PI / 2.0)
}

// Tangent function
func tan(float x) float {
    float c = cos(x)
    if abs(c) < EPSILON { 
        if x > 0 { return INF } else { return NEG_INF }
    }
    sin(x) / c
}

// Arcsine (inverse sine) - returns radians in [-π/2, π/2]
func asin(float x) float {
    // Clamp input
    if x > 1.0 { x = 1.0 }
    if x < -1.0 { x = -1.0 }
    
    // Newton's method
    float guess = x  // asin(x) ≈ x for small x
    int i = 0
    while i < 20 {
        float sg = sin(guess)
        if abs(sg - x) < EPSILON { break }
        float cg = cos(guess)
        if abs(cg) < EPSILON { break }
        guess = guess + (x - sg) / cg
        i = i + 1
    }
    guess
}

// Arccosine
func acos(float x) float {
    PI / 2.0 - asin(x)
}

// Arctangent
func atan(float x) float {
    if x > 1e10 { return PI / 2.0 }
    if x < -1e10 { return -PI / 2.0 }
    if x == 0 { return 0.0 }
    
    // Use atan(x) ≈ x - x³/3 + x⁵/5 - ... for |x| ≤ 1
    // For |x| > 1: atan(x) = π/2 - atan(1/x)
    bool invert = false
    if abs(x) > 1.0 {
        x = 1.0 / x
        invert = true
    }
    
    float xx = x * x
    float term = x
    float sum = x
    int i = 1
    while i <= 15 {
        float coeff = 1.0 / (2.0 * i + 1.0)
        term = term * (-xx)
        sum = sum + term * coeff
        i = i + 1
    }
    
    if invert {
        if sum > 0 { return PI / 2.0 - sum }
        return -PI / 2.0 - sum
    }
    sum
}

// Arctangent of y/x (quadrant-aware)
func atan2(float y, float x) float {
    if x > 0 { return atan(y / x) }
    if x < 0 && y >= 0 { return atan(y / x) + PI }
    if x < 0 && y < 0 { return atan(y / x) - PI }
    if y > 0 { return PI / 2.0 }
    if y < 0 { return -PI / 2.0 }
    0.0  // both zero
}

// Hyperbolic functions (双曲函数)
func sinh(float x) float {
    (exp(x) - exp(-x)) / 2.0
}

func cosh(float x) float {
    (exp(x) + exp(-x)) / 2.0
}

func tanh(float x) float {
    float ep = exp(x)
    float em = exp(-x)
    (ep - em) / (ep + em)
}

// Inverse hyperbolic
func asinh(float x) float {
    log(x + sqrt(x*x + 1.0))
}

func acosh(float x) float {
    log(x + sqrt(x*x - 1.0))
}

func atanh(float x) float {
    log((1.0 + x) / (1.0 - x)) / 2.0
}

// ============================================
// Rounding Functions (取整函数)
// ============================================

func ceil(float x) float {
    int ix = x as int
    if x > ix as float && x >= 0 { return (ix + 1) as float }
    if x != ix as float && x < 0 { return ix as float }
    x
}

func floor(float x) float {
    int ix = x as int
    if x < ix as float && x < 0 { return (ix - 1) as float }
    if x != ix as float && x >= 0 { return ix as float }
    x
}

func round(float x) float {
    if x >= 0 { return floor(x + 0.5) }
    return ceil(x - 0.5)
}

func trunc(float x) float {
    x as int as float
}

// ============================================
// Deep Learning Activation Functions (DL 激活函数)
// ============================================

// Sigmoid: 1 / (1 + e^{-x})
func sigmoid(float x) float {
    if x > 500 { return 1.0 }
    if x < -500 { return 0.0 }
    float ep = exp(-x)
    1.0 / (1.0 + ep)
}

// ReLU: max(0, x)
func relu(float x) float {
    if x < 0 { return 0.0 }
    x
}

// Leaky ReLU
func leaky_relu(float x, float negative_slope) float {
    if x < 0 { return x * negative_slope }
    x
}

// GELU (Gaussian Error Linear Unit) - approximate version used in GPT-2/3
func gelu(float x) float {
    // GELU(x) ≈ 0.5 * x * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x³)))
    float sqrt_2_over_pi = 0.7978845608028654
    float inner = sqrt_2_over_pi * (x + 0.044715 * x * x * x)
    0.5 * x * (1.0 + tanh(inner))
}

// SiLU / Swish: x * sigmoid(x)
func silu(float x) float {
    x * sigmoid(x)
}

// Softplus: log(1 + e^x)
func softplus(float x) float {
    if x > 20 { return x }
    if x < -20 { return 0.0 }
    log1p(exp(x))
}

// ELU: x if x > 0, else α(e^x - 1)
func elu(float x, float alpha) float {
    if x > 0 { return x }
    alpha * (exp(x) - 1.0)
}

// Mish: x * tanh(softplus(x))
func mish(float x) float {
    x * tanh(softplus(x))
}

// Softmax for a single value (component of vector softmax)
// Note: Full softmax requires knowing all values for normalization
func softmax_component(float x, float max_x, float sum_exp) float {
    exp(x - max_x) / sum_exp
}

// Log-sum-exp (numerically stable)
func log_sum_exp(float[] values, int count) float {
    if count <= 0 { return 0.0 }
    
    float m = values[0]
    int i = 1
    while i < count {
        m = max(m, values[i])
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

// ============================================
// Interpolation & Special Functions
// ============================================

// Linear interpolation
func lerp(float a, float b, float t) float {
    a + t * (b - a)
}

// Smooth step (Hermite interpolation)
func smoothstep(float edge0, float edge1, float x) float {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    t * t * (3.0 - 2.0 * t)
}

// Error function approximation (for normal distribution CDF)
func erf(float x) float {
    // Abramowitz and Stegun approximation
    float sign = 1.0
    if x < 0 { sign = -1.0; x = -x }
    
    float t = 1.0 / (1.0 + 0.3275911 * x)
    float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) 
                + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
    
    sign * y
}

// Complementary error function
func erfc(float x) float {
    1.0 - erf(x)
}

// Standard normal CDF: Φ(x) = 0.5 * (1 + erf(x / sqrt(2)))
func normal_cdf(float x) float {
    0.5 * (1.0 + erf(x / SQRT2))
}

// Standard normal PDF: φ(x) = exp(-x²/2) / sqrt(2π)
func normal_pdf(float x) float {
    exp(-0.5 * x * x) / (SQRT2 * sqrt(PI))
}

// ============================================
// Distance & Similarity Functions
// ============================================

// Euclidean distance between two scalars
func euclidean_distance(float a, float b) float {
    abs(a - b)
}

// Squared L2 distance
func l2_distance_sq(float a, float b) float {
    float d = a - b
    d * d
}

// Manhattan (L1) distance
func l1_distance(float a, float b) float {
    abs(a - b)
}

// Cosine similarity for scalars (always ±1 or 0 if one is 0)
func cosine_similarity(float a, float b) float {
    float norm_a = abs(a)
    float norm_b = abs(b)
    if norm_a < EPSILON || norm_b < EPSILON { return 0.0 }
    (a * b) / (norm_a * norm_b)
}
