// Minimal bootstrap test: demonstrates that the native compiler
// can successfully compile a simple program that uses only int-based operations
// This validates the bootstrap chain works in principle

package test.native_bootstrap

// Simple arithmetic - the native frontend should be able to handle this
func add(int a, int b) int {
    return a + b
}

func multiply(int x, int y) int {
    return x * y
}

func factorial(int n) int {
    if n <= 1 {
        return 1
    }
    return n * factorial(n - 1)
}

// Main entry point
func main() int {
    // Test basic operations
    result1 := add(5, 3)       // 8
    result2 := multiply(4, 7)   // 28
    result3 := factorial(5)     // 120
    
    // Return a value that encodes success of all tests
    // If all operations work correctly, should return 156
    return result1 + result2 + result3
}
