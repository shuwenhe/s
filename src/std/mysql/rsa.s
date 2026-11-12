package std.mysql
import ("std.database"; "std.database.wire"; "std.crypto")

// RSA public-key encryption only. No private-key operations. OAEP SHA-1 is
// mandated by caching_sha2_password. 2048..4096-bit SPKI PEM keys, odd exponent.
func _rsa_error() std.database.error { return std.database.failure(std.database.error_authentication,"invalid RSA public key or OAEP message size") }
func _der(std.database.wire.cursor* source, int tag) string {
    actual := std.database.wire.read_byte(source*)
    size := std.database.wire.read_byte(source*)
    if actual != tag { source.code = std.database.error_protocol; return "" }
    if size >= 128 {
        width := size - 128
        if width < 1 || width > 2 { source.code = std.database.error_protocol; return "" }
        size = std.database.wire.read_uint(source*,width,false)
    }
    return std.database.wire.read_bytes(source*,size)
}
func _pem_der(string pem) (string,std.database.error) {
    header := "-----BEGIN PUBLIC KEY-----"
    footer := "-----END PUBLIC KEY-----"
    if len(pem) > 4096 || len(pem) < len(header) + len(footer) { return "",_rsa_error() }
    if std.database._slice(pem,0,len(header)) != header { return "",_rsa_error() }
    output := ""
    index := len(header)
    bits := 0
    accumulator := 0
    padding := false
    while index < len(pem) {
        byte := std.database._byte(pem,index)
        if byte == 45 { break }
        index = index + 1
        if byte == 10 || byte == 13 || byte == 32 || byte == 9 { continue }
        if byte == 61 { padding = true; continue }
        if padding { return "",_rsa_error() }
        digit := -1
        if byte >= 65 && byte <= 90 { digit = byte - 65 }
        if byte >= 97 && byte <= 122 { digit = byte - 71 }
        if byte >= 48 && byte <= 57 { digit = byte + 4 }
        if byte == 43 { digit = 62 }
        if byte == 47 { digit = 63 }
        if digit < 0 { return "",_rsa_error() }
        accumulator = accumulator * 64 + digit
        bits = bits + 6
        if bits >= 8 {
            bits = bits - 8
            output = output + std.database.__std_byte_string((accumulator >> bits) & 255)
            accumulator = accumulator & ((1 << bits) - 1)
        }
    }
    if len(pem) - index < len(footer) { return "",_rsa_error() }
    if std.database._slice(pem,index,index + len(footer)) != footer || accumulator != 0 { return "",_rsa_error() }
    index = index + len(footer)
    while index < len(pem) {
        byte := std.database._byte(pem,index)
        if byte != 10 && byte != 13 && byte != 32 { return "",_rsa_error() }
        index = index + 1
    }
    return output,std.database.error {}
}
func _mgf1(string seed, int size) string {
    result := ""
    counter := 0
    while len(result) < size {
        serial,error := std.database.wire.encode_uint(counter,4,false)
        block,hash_error := std.crypto.sha1(seed + serial)
        if error.code != 0 || hash_error.code != 0 { return "" }
        result = result + block
        counter = counter + 1
    }
    return std.database._slice(result,0,size)
}
func _xor(string first, string second) string {
    result := ""
    index := 0
    while index < len(first) {
        result = result + std.database.__std_byte_string(std.database._byte(first,index) ^ std.database._byte(second,index))
        index = index + 1
    }
    return result
}
func _limbs(string bytes, int count) int[] {
    limbs := make([]int,count)
    index := len(bytes)
    carry := 0
    bits := 0
    position := 0
    while index > 0 {
        index = index - 1
        carry = carry | (std.database._byte(bytes,index) << bits)
        bits = bits + 8
        if bits >= 30 {
            limbs[position] = carry & 1073741823
            position = position + 1
            carry = carry >> 30
            bits = bits - 30
        }
    }
    if bits > 0 { limbs[position] = carry }
    return limbs
}
func _mod_add(int[] target, int[] other, int[] modulus) int[] {
    carry := 0
    index := 0
    while index < len(target) {
        sum := target[index] + other[index] + carry
        target[index] = sum & 1073741823
        carry = sum >> 30
        index = index + 1
    }
    index = len(target) - 1
    while index > 0 && target[index] == modulus[index] { index = index - 1 }
    if target[index] < modulus[index] { return target }
    borrow := 0
    index = 0
    while index < len(target) {
        difference := target[index] - modulus[index] - borrow
        borrow = 0
        if difference < 0 { difference = difference + 1073741824; borrow = 1 }
        target[index] = difference
        index = index + 1
    }
    return target
}
// Coarsely integrated operand scanning Montgomery product, radix 2^30.
// Products plus carries fit signed 64-bit (and Seed's signed 63-bit payload).
func _montgomery(int[] first, int[] second, int[] modulus, int inverse) int[] {
    count := len(modulus) - 1
    temporary := make([]int,count + 2)
    outer := 0
    while outer < count {
        carry := 0
        inner := 0
        while inner < count {
            total := temporary[inner] + first[inner] * second[outer] + carry
            temporary[inner] = total & 1073741823
            carry = total >> 30
            inner = inner + 1
        }
        total := temporary[count] + carry
        temporary[count] = total & 1073741823
        temporary[count + 1] = total >> 30
        factor := (temporary[0] * inverse) & 1073741823
        carry = 0
        inner = 0
        while inner < count {
            combined := temporary[inner] + factor * modulus[inner] + carry
            if inner > 0 { temporary[inner - 1] = combined & 1073741823 }
            carry = combined >> 30
            inner = inner + 1
        }
        combined := temporary[count] + carry
        temporary[count - 1] = combined & 1073741823
        temporary[count] = temporary[count + 1] + (combined >> 30)
        temporary[count + 1] = 0
        outer = outer + 1
    }
    result := make([]int,count + 1)
    index := 0
    while index <= count { result[index] = temporary[index]; index = index + 1 }
    zero := make([]int,count + 1)
    return _mod_add(result,zero,modulus)
}
func rsa_password(string password, string scramble, string pem) (string,std.database.error) {
    if len(password) > 4096 || len(scramble) != 20 { return "",_rsa_error() }
    // MySQL-generated public_key.pem may include its C-string terminator.
    normalized_pem := pem
    if len(pem) > 0 && std.database._byte(pem,len(pem) - 1) == 0 { normalized_pem = std.database._slice(pem,0,len(pem) - 1) }
    der,error := _pem_der(normalized_pem)
    if error.code != 0 { return "",error }
    outer := std.database.wire.cursor { data: der }
    sequence := _der(outer*,48)
    if outer.code != 0 || outer.position != len(der) { return "",_rsa_error() }
    spki := std.database.wire.cursor { data: sequence }
    algorithm := _der(spki*,48)
    expected,hex_error := std.crypto.unhex("06092a864886f70d0101010500")
    if hex_error.code != 0 || algorithm != expected { return "",_rsa_error() }
    bit_string := _der(spki*,3)
    if spki.code != 0 || spki.position != len(sequence) || len(bit_string) < 2 || std.database._byte(bit_string,0) != 0 { return "",_rsa_error() }
    key := std.database.wire.cursor { data: std.database._slice(bit_string,1,len(bit_string)) }
    integers := _der(key*,48)
    if key.code != 0 || key.position != len(bit_string) - 1 { return "",_rsa_error() }
    numbers := std.database.wire.cursor { data: integers }
    modulus_bytes := _der(numbers*,2)
    exponent_bytes := _der(numbers*,2)
    if numbers.code != 0 || numbers.position != len(integers) || len(modulus_bytes) == 0 || len(exponent_bytes) < 1 || len(exponent_bytes) > 4 { return "",_rsa_error() }
    if std.database._byte(modulus_bytes,0) == 0 { modulus_bytes = std.database._slice(modulus_bytes,1,len(modulus_bytes)) }
    width := len(modulus_bytes)
    if width < 256 || width > 512 || len(password) + 1 > width - 42 { return "",_rsa_error() }
    if std.database._byte(modulus_bytes,0) < 128 || (std.database._byte(modulus_bytes,width - 1) & 1) == 0 { return "",_rsa_error() }
    exponent_cursor := std.database.wire.cursor { data: exponent_bytes }
    exponent_width := len(exponent_bytes)
    exponent := std.database.wire.read_uint(exponent_cursor*,exponent_width,false)
    if exponent < 3 || exponent > 2147483647 || (exponent & 1) == 0 { return "",_rsa_error() }
    raw := password + std.database.__std_byte_string(0)
    mask := ""
    index := 0
    while index < len(raw) { mask = mask + std.database.__std_byte_string(std.database._byte(scramble,index % 20)); index = index + 1 }
    message := _xor(raw,mask)
    label,hash_error := std.crypto.sha1("")
    if hash_error.code != 0 { return "",_rsa_error() }
    db := label
    while len(db) < width - len(message) - 22 { db = db + std.database.__std_byte_string(0) }
    db = db + std.database.__std_byte_string(1) + message
    seed,random_error := std.crypto.random_bytes(20)
    if random_error.code != 0 { return "",std.database.failure(std.database.error_authentication,"OS entropy unavailable") }
    masked_db := _xor(db,_mgf1(seed,width - 21))
    encoded := std.database.__std_byte_string(0) + _xor(seed,_mgf1(masked_db,20)) + masked_db
    count := (width * 8 + 29) / 30
    modulus := _limbs(modulus_bytes,count + 1)
    power := _limbs(encoded,count + 1)
    result := make([]int,count + 1)
    result[0] = 1
    index = 0
    while index < count * 30 {
        power = _mod_add(power,power,modulus)
        result = _mod_add(result,result,modulus)
        index = index + 1
    }
    inverse := 1
    index = 0
    while index < 5 {
        product := (modulus[0] * inverse) & 1073741823
        inverse = (inverse * (2 - product)) & 1073741823
        index = index + 1
    }
    inverse = (1073741824 - inverse) & 1073741823
    while exponent > 0 {
        if (exponent & 1) != 0 { result = _montgomery(result,power,modulus,inverse) }
        exponent = exponent >> 1
        if exponent > 0 { power = _montgomery(power,power,modulus,inverse) }
    }
    one := make([]int,count + 1)
    one[0] = 1
    result = _montgomery(result,one,modulus,inverse)
    output := ""
    index = 0
    while index < width {
        offset := index * 8
        limb := offset / 30
        shift := offset % 30
        byte := (result[limb] >> shift) & 255
        if shift > 22 { byte = byte | ((result[limb + 1] << (30 - shift)) & 255) }
        output = std.database.__std_byte_string(byte) + output
        index = index + 1
    }
    return output,std.database.error {}
}
