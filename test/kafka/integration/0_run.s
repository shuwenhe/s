package main

func main() int {
    var result int = 0
    
    if apiversions_checks() != 0 {
        result = 1
    }
    
    if result == 0 && broker_checks() != 0 {
        result = 2
    }
    
    if result == 0 && metadata_checks() != 0 {
        result = 3
    }
    
    return result
}
