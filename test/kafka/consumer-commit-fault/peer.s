package main
import ("std.kafka"; "std.tcp"; "std.time")
extern "intrinsic" func host_args() string[]
func receive(std.tcp.socket* socket, int size) (string,int) {
    output := ""
    while len(output) < size {
        maximum := size - len(output)
        chunk, problem := std.tcp.read_some(socket*, maximum, 3000)
        if problem.code != 0 || chunk.eof || len(chunk.data) == 0 { return "", 1 }
        output = output + chunk.data
    }
    return output, 0
}
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    listener, listen_error := std.tcp.listen_ipv4("127.0.0.1", 19096, 4)
    if listen_error.code != 0 { return 1 }
    println("ready")
    commits := 0
    while true {
      socket, accept_error := std.tcp.accept(listener, 5000)
      if accept_error.code != 0 { return 2 }
      reconnect := false
      while true {
        header, header_error := receive(socket*, 4)
        if header_error != 0 { return 3 }
        h := std.kafka.new_cursor(header, 4)
        size := std.kafka.read_int(h*, 4)
        if size < 10 || size > 1048576 { return 4 }
        request, request_error := receive(socket*, size)
        if request_error != 0 { return 5 }
        r := std.kafka.new_cursor(request, 1048576)
        api := std.kafka.read_int(r*, 2)
        version := std.kafka.read_int(r*, 2)
        correlation := std.kafka.read_int(r*, 4)
        client := std.kafka.read_nullable(r*, 2, 32767)
        w := std.kafka.new_writer(1024)
        std.kafka.put_int(w*, correlation, 4)
        if api == 18 {
            if version != 0 { return 6 }
            std.kafka.put_int(w*, 0, 2)
            std.kafka.put_int(w*, 1, 4)
            std.kafka.put_int(w*, 8, 2)
            std.kafka.put_int(w*, 2, 2)
            std.kafka.put_int(w*, 2, 2)
        } else {
            if api != 8 || version != 2 { return 7 }
            group := std.kafka.read_string(r*, 255)
            generation := std.kafka.read_int(r*, 4)
            member := std.kafka.read_string(r*, 32767)
            retention := std.kafka.read_int(r*, 8)
            topics := std.kafka.read_int(r*, 4)
            topic := std.kafka.read_string(r*, 249)
            count := std.kafka.read_int(r*, 4)
            expected := 1
            if mode == "partial" && commits == 0 { expected = 2 }
            if group != "commit-group" || generation != 7 || member != "member" || topics != 1 || topic != "topic" || count != expected { return 8 }
            std.kafka.put_int(w*, 1, 4)
            std.kafka.put_string(w*, topic)
            std.kafka.put_int(w*, count, 4)
            i := 0
            while i < count {
                partition_id := std.kafka.read_int(r*, 4)
                offset := std.kafka.read_int(r*, 8)
                metadata := std.kafka.read_nullable(r*, 2, 32767)
                if (partition_id == 0 && offset != 45) || (partition_id == 1 && offset != 20) || partition_id < 0 || partition_id > 1 { return 9 }
                status := 0
                if commits == 0 && mode == "auth" { status = 30 }
                if commits == 0 && mode == "partial" && partition_id == 1 { status = 7 }
                std.kafka.put_int(w*, partition_id, 4)
                std.kafka.put_int(w*, status, 2)
                i = i + 1
            }
            if std.kafka.finished(r*).code != 0 { return 10 }
            commits = commits + 1
            if commits == 1 && (mode == "lost" || mode == "timeout") {
                if mode == "timeout" { std.time.sleep_ms(300) }
                std.tcp.close(socket*)
                reconnect = true
                break
            }
        }
        framed := std.kafka.new_writer(1024)
        frame_size := len(w.data)
        std.kafka.put_int(framed*, frame_size, 4)
        std.kafka.put_raw(framed*, w.data)
        response := framed.data
        written, write_error := std.tcp.write_all(socket*, response, 1000)
        if write_error.code != 0 { return 13 }
        if api == 8 && (commits == 2 || mode == "auth") { break }
    }
      std.tcp.close(socket*)
      if !reconnect { break }
    }
    std.tcp.close(listener*)
    println("Native commit peer validated generation/member/ACK offset: PASS")
    return 0
}
