package main

// Non-move fixture: S12.2 should observe move-count = 0
// This fixture contains only copy/assign operations, no moves

struct Value {
    data int
}

func main() string {
    // Copy operation only (copyable type or explicit Copy)
    val1 := Value { data: 123 }
    val2 := val1  // COPY: val1 is copied to val2 (not moved)
    
    // Immutable borrow, no move
    result := describe_value(val1)
    
    // Another assignment (still no move if Copy)
    val3 := val2
    
    return result
}

func describe_value(v Value) string {
    return "value with data"
}
