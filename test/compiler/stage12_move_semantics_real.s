package main

// Real move fixture: S12.2 should observe move facts extracted from MIR
// This fixture contains actual move operations that should appear in MIR

func helper() int {
    return 7
}

func main() int {
    // Loan 1: Create owned box and borrow it
    owner := box(42)
    reader := &owner

    // Move 1: Create a separate owned box and move it
    box1 := box(7)
    box2 := box1  // MOVE: box1 value moved to box2
    
    return *reader + *box2
}
