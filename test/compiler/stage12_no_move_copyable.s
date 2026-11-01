package main

struct Value {
    data int
}

func main() string {
    
    val1 := Value { data: 123 }
    val2 := val1  
    
    
    result := describe_value(val1)
    
    
    val3 := val2
    
    return result
}

func describe_value(v Value) string {
    return "value with data"
}
