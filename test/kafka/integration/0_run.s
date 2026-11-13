package main

func main() int {
    println("=== Kafka Integration Tests ===")
    
    status := 0
    
    println("Phase 2.1: ApiVersions protocol checks")
    if apiversions_checks() != 0 {
        println("FAIL: apiversions_checks")
        status = 1
    } else {
        println("PASS: apiversions_checks")
    }
    
    println("Phase 2.2: Broker connection checks")
    if broker_checks() != 0 {
        println("FAIL: broker_checks")
        status = 2
    } else {
        println("PASS: broker_checks")
    }
    
    println("Phase 2.3: Metadata discovery checks")
    if metadata_checks() != 0 {
        println("FAIL: metadata_checks")
        status = 3
    } else {
        println("PASS: metadata_checks")
    }
    
    return status
}
