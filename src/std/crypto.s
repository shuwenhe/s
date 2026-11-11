package std.crypto
import "std.result"

// Byte strings in/out. SHA-1 exists solely for protocol compatibility. Hash input
// is bounded to 1 MiB; PBKDF2 callers must choose an explicit work factor.
struct crypto_error { int code, string operation }
extern "intrinsic" func __host_byte_at(string text, int index) int
extern "intrinsic" func __std_byte_string(int value) string
extern "intrinsic" func __string_slice(string text, int start, int end) string
extern "intrinsic" func __crypto_random(int count) int[]
func _error(int code, string operation) crypto_error { return crypto_error { code: code, operation: operation } }
func _right(int value, int count) int { return ((value >> count) | ((value << (32 - count)) & 4294967295)) }
func _left(int value, int count) int { return (((value << count) & 4294967295) | (value >> (32 - count))) }
func _word(string text, int index) int {
    return __host_byte_at(text,index) * 16777216 + __host_byte_at(text,index + 1) * 65536 + __host_byte_at(text,index + 2) * 256 + __host_byte_at(text,index + 3)
}
func _word_bytes(int value) string {
    return __std_byte_string((value >> 24) & 255) + __std_byte_string((value >> 16) & 255) + __std_byte_string((value >> 8) & 255) + __std_byte_string(value & 255)
}
func _padded(string input) string {
    bytes := input + __std_byte_string(128)
    while len(bytes) % 64 != 56 { bytes = bytes + __std_byte_string(0) }
    return bytes + _word_bytes(0) + _word_bytes(len(input) * 8)
}
func sha256(string input) (string,crypto_error) {
    if len(input) > 1048576 { return "", _error(22,"SHA-256 input limit") }
    k := int[]{1116352408,1899447441,3049323471,3921009573,961987163,1508970993,2453635748,2870763221,3624381080,310598401,607225278,1426881987,1925078388,2162078206,2614888103,3248222580,3835390401,4022224774,264347078,604807628,770255983,1249150122,1555081692,1996064986,2554220882,2821834349,2952996808,3210313671,3336571891,3584528711,113926993,338241895,666307205,773529912,1294757372,1396182291,1695183700,1986661051,2177026350,2456956037,2730485921,2820302411,3259730800,3345764771,3516065817,3600352804,4094571909,275423344,430227734,506948616,659060556,883997877,958139571,1322822218,1537002063,1747873779,1955562222,2024104815,2227730452,2361852424,2428436474,2756734187,3204031479,3329325298}
    h := int[]{1779033703,3144134277,1013904242,2773480762,1359893119,2600822924,528734635,1541459225}
    bytes := _padded(input)
    w := make([]int,64)
    block := 0
    while block < len(bytes) {
        index := 0
        while index < 16 { w[index] = _word(bytes,block + index * 4); index = index + 1 }
        while index < 64 {
            x := w[index - 15]
            y := w[index - 2]
            s0 := _right(x,7) ^ _right(x,18) ^ (x >> 3)
            s1 := _right(y,17) ^ _right(y,19) ^ (y >> 10)
            w[index] = (w[index - 16] + s0 + w[index - 7] + s1) & 4294967295
            index = index + 1
        }
        a := h[0]
        b := h[1]
        c := h[2]
        d := h[3]
        e := h[4]
        f := h[5]
        g := h[6]
        v := h[7]
        index = 0
        while index < 64 {
            s1 := _right(e,6) ^ _right(e,11) ^ _right(e,25)
            choice := (e & f) ^ ((4294967295 - e) & g)
            t1 := (v + s1 + choice + k[index] + w[index]) & 4294967295
            s0 := _right(a,2) ^ _right(a,13) ^ _right(a,22)
            majority := (a & b) ^ (a & c) ^ (b & c)
            t2 := (s0 + majority) & 4294967295
            v = g
            g = f
            f = e
            e = (d + t1) & 4294967295
            d = c
            c = b
            b = a
            a = (t1 + t2) & 4294967295
            index = index + 1
        }
        h[0] = (h[0] + a) & 4294967295
        h[1] = (h[1] + b) & 4294967295
        h[2] = (h[2] + c) & 4294967295
        h[3] = (h[3] + d) & 4294967295
        h[4] = (h[4] + e) & 4294967295
        h[5] = (h[5] + f) & 4294967295
        h[6] = (h[6] + g) & 4294967295
        h[7] = (h[7] + v) & 4294967295
        block = block + 64
    }
    output := ""
    index := 0
    while index < 8 { output = output + _word_bytes(h[index]); index = index + 1 }
    return output,crypto_error { code: 0 }
}
func sha1(string input) (string,crypto_error) {
    if len(input) > 1048576 { return "", _error(22,"SHA-1 input limit") }
    h := int[]{1732584193,4023233417,2562383102,271733878,3285377520}
    bytes := _padded(input)
    w := make([]int,80)
    block := 0
    while block < len(bytes) {
        index := 0
        while index < 16 { w[index] = _word(bytes,block + index * 4); index = index + 1 }
        while index < 80 {
            w[index] = _left(w[index - 3] ^ w[index - 8] ^ w[index - 14] ^ w[index - 16],1)
            index = index + 1
        }
        a := h[0]
        b := h[1]
        c := h[2]
        d := h[3]
        e := h[4]
        index = 0
        while index < 80 {
            f := b ^ c ^ d
            k := 1859775393
            if index < 20 { f = (b & c) | ((4294967295 - b) & d); k = 1518500249 }
            if index >= 40 && index < 60 { f = (b & c) | (b & d) | (c & d); k = 2400959708 }
            if index >= 60 { k = 3395469782 }
            temp := (_left(a,5) + f + e + k + w[index]) & 4294967295
            e = d
            d = c
            c = _left(b,30)
            b = a
            a = temp
            index = index + 1
        }
        h[0] = (h[0] + a) & 4294967295
        h[1] = (h[1] + b) & 4294967295
        h[2] = (h[2] + c) & 4294967295
        h[3] = (h[3] + d) & 4294967295
        h[4] = (h[4] + e) & 4294967295
        block = block + 64
    }
    return _word_bytes(h[0]) + _word_bytes(h[1]) + _word_bytes(h[2]) + _word_bytes(h[3]) + _word_bytes(h[4]),crypto_error { code: 0 }
}
func hmac_sha256(string key, string message) (string,crypto_error) {
    if len(key) > 1048576 || len(message) > 1048512 { return "", _error(22,"HMAC input limit") }
    normalized := key
    if len(key) > 64 {
        digest,error := sha256(key)
        if error.code != 0 { return "",error }
        normalized = digest
    }
    inner := ""
    outer := ""
    index := 0
    while index < 64 {
        byte := 0
        if index < len(normalized) { byte = __host_byte_at(normalized,index) }
        inner = inner + __std_byte_string(byte ^ 54)
        outer = outer + __std_byte_string(byte ^ 92)
        index = index + 1
    }
    hash,error := sha256(inner + message)
    if error.code != 0 { return "",error }
    return sha256(outer + hash)
}
func pbkdf2_sha256(string password, string salt, int iterations, int length) (string,crypto_error) {
    if iterations < 1 || iterations > 1000000 || length < 0 || length > 1024 || len(password) > 1048576 || len(salt) > 1048508 { return "", _error(22,"PBKDF2 bounds") }
    output := ""
    block := 1
    while len(output) < length {
        u,error := hmac_sha256(password,salt + _word_bytes(block))
        if error.code != 0 { return "",error }
        combined := u
        round := 1
        while round < iterations {
            next,next_error := hmac_sha256(password,u)
            if next_error.code != 0 { return "",next_error }
            u = next
            mixed := ""
            index := 0
            while index < 32 {
                mixed = mixed + __std_byte_string(__host_byte_at(combined,index) ^ __host_byte_at(u,index))
                index = index + 1
            }
            combined = mixed
            round = round + 1
        }
        remaining := length - len(output)
        if remaining < 32 { combined = __string_slice(combined,0,remaining) }
        output = output + combined
        block = block + 1
    }
    return output,crypto_error { code: 0 }
}
func constant_time_equal(string left, string right) bool {
    if len(left) != len(right) { return false }
    difference := 0
    index := 0
    while index < len(left) {
        difference = difference | (__host_byte_at(left,index) ^ __host_byte_at(right,index))
        index = index + 1
    }
    return difference == 0
}
func hex(string bytes) string {
    digits := "0123456789abcdef"
    output := ""
    index := 0
    while index < len(bytes) {
        byte := __host_byte_at(bytes,index)
        output = output + __std_byte_string(__host_byte_at(digits,byte / 16)) + __std_byte_string(__host_byte_at(digits,byte % 16))
        index = index + 1
    }
    return output
}
func _hex_digit(int byte) int {
    if byte >= 48 && byte <= 57 { return byte - 48 }
    if byte >= 97 && byte <= 102 { return byte - 87 }
    if byte >= 65 && byte <= 70 { return byte - 55 }
    return -1
}
func unhex(string text) (string,crypto_error) {
    if len(text) % 2 != 0 { return "", _error(22,"odd hex length") }
    output := ""
    index := 0
    while index < len(text) {
        high := _hex_digit(__host_byte_at(text,index))
        low := _hex_digit(__host_byte_at(text,index + 1))
        if high < 0 || low < 0 { return "", _error(22,"invalid hex digit") }
        output = output + __std_byte_string(high * 16 + low)
        index = index + 2
    }
    return output,crypto_error { code: 0 }
}
func random_bytes(int count) (string,crypto_error) {
    if count < 0 || count > 65536 { return "", _error(22,"random byte count") }
    bytes := __crypto_random(count)
    if len(bytes) == 0 { return "", _error(12,"entropy allocation") }
    if bytes[0] < 0 { return "", _error(0 - bytes[0],"getrandom") }
    if len(bytes) != count + 1 { return "", _error(5,"short entropy result") }
    output := ""
    index := 1
    while index < len(bytes) { output = output + __std_byte_string(bytes[index]); index = index + 1 }
    return output,crypto_error { code: 0 }
}
