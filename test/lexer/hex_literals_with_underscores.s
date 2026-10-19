// Test hexadecimal literals with underscores
// Validates both Seed and Production Lexer support for 0x_XX format

func test_hex_basic() int {
    // Basic hex without underscores
    a := 0xff
    if a != 255 { return 1 }
    
    b := 0xFF
    if b != 255 { return 2 }
    
    c := 0x0
    if c != 0 { return 3 }
    
    return 0
}

func test_hex_with_underscores() int {
    // Hex with underscore after prefix
    a := 0x_b8
    if a != 184 { return 1 }
    
    b := 0x_ff
    if b != 255 { return 2 }
    
    c := 0x_00
    if c != 0 { return 3 }
    
    return 0
}

func test_hex_underscores_mixed() int {
    // Hex with underscores in middle and after prefix
    a := 0x1_000
    if a != 4096 { return 1 }
    
    b := 0xff_ff
    if b != 65535 { return 2 }
    
    c := 0x_ff_ff
    if c != 65535 { return 3 }
    
    d := 0x840_f
    if d != 33807 { return 4 }  // 0x840f = 33807
    
    return 0
}

func test_hex_operations() int {
    // Test hex literals in operations (from direct_amd64_gen.s style)
    x := (0x_b8 + 5) as int8
    if x != 189 { return 1 }
    
    y := (100 & 0x_ff) as int8
    if y != 100 { return 2 }
    
    z := ((200 >> 8) & 0x_ff) as int8
    if z != 0 { return 3 }
    
    return 0
}

func main() int {
    if test_hex_basic() != 0 { return 1 }
    if test_hex_with_underscores() != 0 { return 2 }
    if test_hex_underscores_mixed() != 0 { return 3 }
    if test_hex_operations() != 0 { return 4 }
    return 0
}
