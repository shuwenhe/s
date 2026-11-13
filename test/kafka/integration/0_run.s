package main

func main() int {
    status := 0
    
    if apiversions_checks() != 0 {
        status = 1
    }
    
    if status == 0 && broker_checks() != 0 {
        status = 2
    }
    
    if status == 0 && metadata_checks() != 0 {
        status = 3
    }
    
    return status
}
