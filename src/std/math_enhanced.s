package std.math

const PI = 3.14159265358979323846
const E = 2.71828182845904523536
const LN2 = 0.69314718055994530942
const LN10 = 2.30258509299404568402
const SQRT2 = 1.41421356237309504880
const EPSILON = 1e-7
const INF = 1e308
const NEG_INF = -1e308

func abs(float x) float {
    if x < 0 { return -x }
    x
}

func max(float a, float b) float {
    if a > b { a } else { b }
}

func min(float a, float b) float {
    if a < b { a } else { b }
}

func clamp(float x, float lo, float hi) float {
    if x < lo { return lo }
    if x > hi { return hi }
    x
}

func sign(float x) float {
    if x > 0 { return 1.0 }
    if x < 0 { return -1.0 }
    0.0
}

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

func mod(int a, int b) int {
    if b == 0 { return 0 }
    int r = a - (a / b) * b
    if (r > 0 && b < 0) || (r < 0 && b > 0) { r = r + b }
    r
}

func fmod(float a, float b) float {
    float r = a - (a as int) / (b as int) * b
    r
}

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

func cbrt(float x) float {
    if x >= 0 { return pow(x, 1.0 / 3.0) }
    return -pow(-x, 1.0 / 3.0)
}

func exp(float x) float {
    if x > 700 { return INF }
    if x < -700 { return 0.0 }

    bool negative = false
    if x < 0 {
        negative = true
        x = -x
    }

    int k = x / LN2
    float r = x - (k as float) * LN2

    float term = 1.0
    float sum = 1.0
    float rn = 1.0
    int n = 1
    while n <= 20 {
        rn = rn * r
        term = term * n
        n = n + 1
    }

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

    while k > 0 {
        sum = sum * 2.0
        k = k - 1
    }

    if negative { return 1.0 / sum }
    sum
}

func log(float x) float {
    if x <= 0 { return NEG_INF }
    if x == 1 { return 0.0 }

    float y = 0.0

    while x >= 2.0 {
        x = x / 2.0
        y = y + LN2
    }
    while x < 1.0 {
        x = x * 2.0
        y = y - LN2
    }

    float guess = x - 1.0
    int i = 0
    while i < 15 {
        float eg = exp(guess)
        guess = guess + 2.0 * (x - eg) / (x + eg)
        i = i + 1
    }

    y + guess
}

func log10(float x) float {
    log(x) / LN10
}

func log2(float x) float {
    log(x) / LN2
}

func log1p(float x) float {
    if abs(x) < 0.01 {
        return x - x*x/2.0 + x*x*x/3.0
    }
    log(1.0 + x)
}

func sin(float x) float {
    x = fmod(x, 2.0 * PI)
    if x > PI { x = x - 2.0 * PI }
    if x < -PI { x = x + 2.0 * PI }

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

func cos(float x) float {
    sin(x + PI / 2.0)
}

func tan(float x) float {
    float c = cos(x)
    if abs(c) < EPSILON { 
        if x > 0 { return INF } else { return NEG_INF }
    }
    sin(x) / c
}

func asin(float x) float {
    if x > 1.0 { x = 1.0 }
    if x < -1.0 { x = -1.0 }

    float guess = x
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

func acos(float x) float {
    PI / 2.0 - asin(x)
}

func atan(float x) float {
    if x > 1e10 { return PI / 2.0 }
    if x < -1e10 { return -PI / 2.0 }
    if x == 0 { return 0.0 }

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

func atan2(float y, float x) float {
    if x > 0 { return atan(y / x) }
    if x < 0 && y >= 0 { return atan(y / x) + PI }
    if x < 0 && y < 0 { return atan(y / x) - PI }
    if y > 0 { return PI / 2.0 }
    if y < 0 { return -PI / 2.0 }
    0.0
}

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

func asinh(float x) float {
    log(x + sqrt(x*x + 1.0))
}

func acosh(float x) float {
    log(x + sqrt(x*x - 1.0))
}

func atanh(float x) float {
    log((1.0 + x) / (1.0 - x)) / 2.0
}

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

func sigmoid(float x) float {
    if x > 500 { return 1.0 }
    if x < -500 { return 0.0 }
    float ep = exp(-x)
    1.0 / (1.0 + ep)
}

func relu(float x) float {
    if x < 0 { return 0.0 }
    x
}

func leaky_relu(float x, float negative_slope) float {
    if x < 0 { return x * negative_slope }
    x
}

func gelu(float x) float {
    float sqrt_2_over_pi = 0.7978845608028654
    float inner = sqrt_2_over_pi * (x + 0.044715 * x * x * x)
    0.5 * x * (1.0 + tanh(inner))
}

func silu(float x) float {
    x * sigmoid(x)
}

func softplus(float x) float {
    if x > 20 { return x }
    if x < -20 { return 0.0 }
    log1p(exp(x))
}

func elu(float x, float alpha) float {
    if x > 0 { return x }
    alpha * (exp(x) - 1.0)
}

func mish(float x) float {
    x * tanh(softplus(x))
}

func softmax_component(float x, float max_x, float sum_exp) float {
    exp(x - max_x) / sum_exp
}

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

func lerp(float a, float b, float t) float {
    a + t * (b - a)
}

func smoothstep(float edge0, float edge1, float x) float {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    t * t * (3.0 - 2.0 * t)
}

func erf(float x) float {
    float sign = 1.0
    if x < 0 { sign = -1.0; x = -x }

    float t = 1.0 / (1.0 + 0.3275911 * x)
    float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) 
                + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)

    sign * y
}

func erfc(float x) float {
    1.0 - erf(x)
}

func normal_cdf(float x) float {
    0.5 * (1.0 + erf(x / SQRT2))
}

func normal_pdf(float x) float {
    exp(-0.5 * x * x) / (SQRT2 * sqrt(PI))
}

func euclidean_distance(float a, float b) float {
    abs(a - b)
}

func l2_distance_sq(float a, float b) float {
    float d = a - b
    d * d
}

func l1_distance(float a, float b) float {
    abs(a - b)
}

func cosine_similarity(float a, float b) float {
    float norm_a = abs(a)
    float norm_b = abs(b)
    if norm_a < EPSILON || norm_b < EPSILON { return 0.0 }
    (a * b) / (norm_a * norm_b)
}
