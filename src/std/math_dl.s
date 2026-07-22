package std.math_dl

const PI = 3.14159265358979323846
const E = 2.71828182845904523536
const LN2 = 0.69314718055994530942
const LN10 = 2.30258509299404568402
const SQRT2 = 1.41421356237309504880
const LOG2E = 1.44269504088896340736
const EPSILON = 1e-7
const INF = 1e308
const NEG_INF = -1e308

func abs(float x) float {
    if x < 0 { return -x }
    x
}

func max_f(float a, float b) float {
    if a > b { a } else { b }
}

func min_f(float a, float b) float {
    if a < b { a } else { b }
}

func clamp_f(float x, float lo, float hi) float {
    if x < lo { return lo }
    if x > hi { return hi }
    x
}

func sign_f(float x) float {
    if x > 0 { return 1.0 }
    if x < 0 { return -1.0 }
    0.0
}

func mod(int a, int b) int {
    if b == 0 { return 0 }
    int r = a - (a / b) * b
    if (r > 0 && b < 0) || (r < 0 && b > 0) { r = r + b }
    r
}

func fmod(float a, float b) float {
    float r = a - (a as int as float / b as int as float) * b
    r
}

func square(float x) float { x * x }

func cube(float x) float { x * x * x }

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

func cbrt(float x) float {
    if x >= 0.0 { pow(x, 1.0 / 3.0) }
    else { -pow(-x, 1.0 / 3.0) }
}

func rsqrt(float x) float {
    if x <= 0.0 { return INF }
    1.0 / sqrt(x)
}

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

func exp(float x) float {
    if x > 709.78 { return INF }
    if x < -745.13 { return 0.0 }

    bool neg = false
    if x < 0 { neg = true; x = -x }

    int k = (x / LN2) as int
    float r = x - (k as float) * LN2

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

func expm1(float x) float {
    if abs(x) < 0.01 {
        return x + x*x/2.0 + x*x*x/6.0
    }
    exp(x) - 1.0
}

func log(float x) float {
    if x <= 0.0 { return NEG_INF }
    if x == 1.0 { return 0.0 }

    float y = 0.0
    while x >= 2.0 { x = x / 2.0; y = y + LN2 }
    while x < 1.0 { x = x * 2.0; y = y - LN2 }

    float guess = x - 1.0
    int i = 0
    while i < 20 {
        float eg = exp(guess)
        guess = guess + 2.0 * (x - eg) / (x + eg)
        i = i + 1
    }
    y + guess
}

func log1p(float x) float {
    if abs(x) < 0.01 {
        return x - x*x/2.0 + x*x*x/3.0
    }
    log(1.0 + x)
}

func log10(float x) float { log(x) / LN10 }

func log2(float x) float { log(x) / LN2 }

func sin(float x) float {
    float TWO_PI = 2.0 * PI
    x = x - ((x / TWO_PI) as int as float) * TWO_PI
    if x > PI { x = x - TWO_PI }
    if x < -PI { x = x + TWO_PI }

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
        float cg = cos(guess)
        if abs(sg - x) < EPSILON { break }
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
    if x == 0.0 { return 0.0 }

    bool invert = false
    if abs(x) > 1.0 { x = 1.0 / x; invert = true }

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

func atan2(float y, float x) float {
    if x > 0.0 { return atan(y / x) }
    if x < 0.0 && y >= 0.0 { return atan(y / x) + PI }
    if x < 0.0 && y < 0.0 { return atan(y / x) - PI }
    if y > 0.0 { return PI / 2.0 }
    if y < 0.0 { return -PI / 2.0 }
    0.0
}

func deg2rad(float degrees) float { degrees * PI / 180.0 }

func rad2deg(float radians) float { radians * 180.0 / PI }

func sinh(float x) float {
    (exp(x) - exp(-x)) / 2.0
}

func cosh(float x) float {
    (exp(x) + exp(-x)) / 2.0
}

func tanh_h(float x) float {
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
    if x > (ix as float) && x >= 0.0 { return (ix + 1) as float }
    if x != (ix as float) && x < 0.0 { return (ix as float) }
    x
}

func floor(float x) float {
    int ix = x as int
    if x < (ix as float) && x < 0.0 { return (ix - 1) as float }
    if x != (ix as float) && x >= 0.0 { return (ix as float) }
    x
}

func round_f(float x) float {
    if x >= 0.0 { floor(x + 0.5) }
    else { ceil(x - 0.5) }
}

func trunc(float x) float {
    (x as int) as float
}

func sigmoid(float x) float {
    if x > 500.0 { return 1.0 }
    if x < -500.0 { return 0.0 }
    float ep = exp(-x)
    1.0 / (1.0 + ep)
}

func relu(float x) float {
    if x < 0.0 { return 0.0 }
    x
}

func leaky_relu(float x, float alpha) float {
    if x < 0.0 { return x * alpha }
    x
}

func gelu(float x) float {
    float SQRT_2_OVER_PI = 0.7978845608028654
    float inner = SQRT_2_OVER_PI * (x + 0.044715 * x * x * x)
    0.5 * x * (1.0 + tanh_h(inner))
}

func silu(float x) float { x * sigmoid(x) }

func softplus(float x) float {
    if x > 20.0 { return x }
    if x < -20.0 { return 0.0 }
    log1p(exp(x))
}

func elu(float x, float alpha) float {
    if x > 0.0 { return x }
    alpha * (exp(x) - 1.0)
}

func mish(float x) float {
    x * tanh_h(softplus(x))
}

func hardswish(float x) float {
    if x < -3.0 { return 0.0 }
    if x > 3.0 { return x }
    x * (x + 3.0) / 6.0
}

func hardshrink(float x, float lambda) float {
    if x > lambda || x < -lambda { return x }
    0.0
}

func softsign(float x) float {
    x / (1.0 + abs(x))
}

func tanh_act(float x) float { tanh_h(x) }

func erf(float x) float {
    float sign = 1.0
    if x < 0.0 { sign = -1.0; x = -x }

    float t = 1.0 / (1.0 + 0.3275911 * x)
    float y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) 
                 + 1.421413741) * t - 0.284496736) * t 
                 + 0.254829592) * t * exp(-(x * x))

    sign * y
}

func erfc(float x) float { 1.0 - erf(x) }

func normal_cdf(float x) float { 0.5 * (1.0 + erf(x / SQRT2)) }

func normal_pdf(float x) float { exp(-0.5 * x * x) / (SQRT2 * sqrt(PI)) }

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

func sigmoid_xent(float x) float {
    if x > 0.0 { return -log(1.0 + exp(-x)) }
    return x - log(1.0 + exp(x))
}

func lerp(float a, float b, float t) float { a + t * (b - a) }

func inv_lerp(float a, float b, float c) float {
    if abs(b - a) < EPSILON { return 0.0 }
    (c - a) / (b - a)
}

func smoothstep(float edge0, float edge1, float x) float {
    float t = clamp_f((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    t * t * (3.0 - 2.0 * t)
}

func smootherstep(float edge0, float edge1, float x) float {
    float t = clamp_f((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

func step(float edge, float x) float {
    if x < edge { return 0.0 }
    1.0
}

func l1_dist(float a, float b) float { abs(a - b) }

func l2_sq_dist(float a, float b) float { 
    float d = a - b; d * d 
}

func l2_dist(float a, float b) float { sqrt(l2_sq_dist(a, b)) }

func cosine_sim(float a, float b) float {
    float na = abs(a)
    float nb = abs(b)
    if na < EPSILON || nb < EPSILON { return 0.0 }
    (a * b) / (na * nb)
}

func is_finite(float x) bool { x > NEG_INF && x < INF }

func is_nan(float x) bool { !(x == x) }

func safe_div(float a, float b, float fallback) float {
    if abs(b) < EPSILON { return fallback }
    a / b
}

func fmt_float(float val, int decimals) string {
    int ival = val as int
    float frac = val - ival as float
    if frac < 0 { frac = -frac }
    string result = ""

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
