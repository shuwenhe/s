package main

func helper() int {
    return 7
}

func main() int {
    
    owner := box(42)
    reader := &owner

    
    box1 := box(7)
    box2 := box1  
    
    return *reader + *box2
}
