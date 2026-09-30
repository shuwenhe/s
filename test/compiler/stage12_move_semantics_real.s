package main

// Real move fixture: S12.2 should observe move facts extracted from MIR
// This fixture contains actual move operations that should appear in MIR

struct Box {
    value int
}

func main() string {
    // Move 1: Create box and move it
    box1 := Box { value: 42 }
    box2 := box1  // MOVE: box1 value moved to box2
    
    // Move 2: Function parameter move
    result := process_box(box2)  // MOVE: box2 value moved into process_box
    
    return result
}

func process_box(b Box) string {
    return "processed"
}
