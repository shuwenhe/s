// Simulate large message assembly performance
// Tests fragment assembly under various payload sizes
package main
import ("std.tcp"; "std.kafka"; "std.time")

func payload_assembly_test(int size_kb) (int, int, int) {
    // Simulate a Fetch response with a payload of size_kb
    // Return: (fragment_depth, assembly_time_us, reassembled_size)
    
    link := std.kafka.consumer_link {}
    
    // Simulate fragmenting the payload into socket reads
    chunk_size := 1024  // 1 KiB per socket read
    total_size := size_kb * 1024
    
    start, _ := std.time.monotonic_clock()
    
    offset := 0
    while offset < total_size {
        chunk_end := offset + chunk_size
        if chunk_end > total_size { chunk_end = total_size }
        
        // Simulate read: create a chunk of data
        chunk := ""
        i := 0
        while i < (chunk_end - offset) {
            chunk = chunk + std.kafka.byte_string((offset + i) % 256)
            i = i + 1
        }
        
        std.kafka._kc_body_append(link*, chunk)
        offset = chunk_end
    }
    
    end, _ := std.time.monotonic_clock()
    elapsed := end - start  // nanoseconds
    elapsed_us := elapsed / 1000
    
    // Collect all fragments
    assembled := std.kafka._kc_body_collect(link.body_fragments)
    
    return len(link.body_fragments), (elapsed_us), len(assembled)
}

func main() int {
    // Test various payload sizes
    test_sizes := make([]int, 6)
    test_sizes[0] = 1      // 1 KiB
    test_sizes[1] = 16     // 16 KiB
    test_sizes[2] = 64     // 64 KiB
    test_sizes[3] = 256    // 256 KiB
    test_sizes[4] = 512    // 512 KiB
    test_sizes[5] = 1024   // 1 MiB
    
    println("Size      Depth  Time(us)  Reassembled")
    println("----------------------------------------")
    
    i := 0
    while i < len(test_sizes) {
        size := test_sizes[i]
        depth, time_us, reassembled := payload_assembly_test(size)
        
        // Format output
        size_str := ""
        if size == 1 { size_str = "1 KiB  " }
        else if size == 16 { size_str = "16 KiB " }
        else if size == 64 { size_str = "64 KiB " }
        else if size == 256 { size_str = "256 KiB" }
        else if size == 512 { size_str = "512 KiB" }
        else if size == 1024 { size_str = "1 MiB  " }
        
        expected := size * 1024
        status := ""
        if reassembled == expected { status = "✓" }
        else { status = "✗" }
        
        println(size_str + "  " + std.kafka.byte_string(depth) + "   " + std.kafka.byte_string(time_us/1000) + "ms    " + status)
        
        if reassembled != expected { return 1 }
        
        i = i + 1
    }
    
    println("Payload assembly benchmark: PASS")
    return 0
}
