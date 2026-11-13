package main

// Single main entry point
func main() int {
    // Run all integration tests sequentially
    if apiversions_checks() != 0 {
        return 1
    }
    if broker_checks() != 0 {
        return 2
    }
    if metadata_checks() != 0 {
        return 3
    }
    return 0
}
