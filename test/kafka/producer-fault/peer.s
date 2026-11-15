package main
import ("std.kafka"; "std.tcp"; "std.time")
extern "intrinsic" func host_args() string[]
func receive(std.tcp.socket* socket, int size) (string, int) {
    output := ""
    while len(output) < size {
        maximum := size - len(output)
        if maximum > 1024 { maximum = 1024 }
        chunk, problem := std.tcp.read_some(socket*, maximum, 2000)
        if problem.code != 0 || chunk.eof || len(chunk.data) == 0 { return "", 1 }
        output = output + chunk.data
    }
    return output, 0
}
func send_body(std.tcp.socket* socket, int correlation, string body) int {
    w := std.kafka.new_writer(4096)
    length := len(body) + 4
    std.kafka.put_int(w*, length, 4)
    std.kafka.put_int(w*, correlation, 4)
    std.kafka.put_raw(w*, body)
    count, problem := std.tcp.write_all(socket*, w.data, 1000)
    if problem.code != 0 || count != len(w.data) { return 1 }
    return 0
}
func main() int {
    args := host_args()
    if len(args) != 2 { return 90 }
    mode := args[1]
    listener, listen_error := std.tcp.listen_ipv4("127.0.0.1", 19092, 4)
    if listen_error.code != 0 { return 1 }
    println("ready")
    socket, accept_error := std.tcp.accept(listener, 5000)
    if accept_error.code != 0 { return 2 }
    std.tcp.close(listener*)
    rounds := 2
    if mode == "valid" || mode == "broker-error" { rounds = 3 }
    round := 0
    while round < rounds {
        header, header_error := receive(socket*, 4)
        if header_error != 0 { return 3 }
        c := std.kafka.new_cursor(header, 4)
        size := std.kafka.read_int(c*, 4)
        if size < 10 || size > 1048576 { return 4 }
        request, request_error := receive(socket*, size)
        if request_error != 0 { return 5 }
        r := std.kafka.new_cursor(request, 1048576)
        key := std.kafka.read_int(r*, 2)
        version := std.kafka.read_int(r*, 2)
        correlation := std.kafka.read_int(r*, 4)
        client := std.kafka.read_string(r*, 32767)
        if correlation != round + 1 || client != "producer-fault" { return 6 }
        if round == 0 {
            if key != 18 || version != 0 || std.kafka.finished(r*).code != 0 { return 7 }
            w := std.kafka.new_writer(100)
            std.kafka.put_int(w*, 0, 2)
            std.kafka.put_int(w*, 1, 4)
            std.kafka.put_int(w*, 0, 2)
            std.kafka.put_int(w*, 0, 2)
            maximum := 3
            if mode == "unsupported" { maximum = 2 }
            std.kafka.put_int(w*, maximum, 2)
            if send_body(socket*, correlation, w.data) != 0 { return 8 }
            if mode == "unsupported" { break }
        } else {
            if key != 0 || version != 3 { return 9 }
            transaction := std.kafka.read_nullable(r*, 2, 100)
            acks := std.kafka.read_int(r*, 2)
            timeout := std.kafka.read_int(r*, 4)
            topics := std.kafka.read_int(r*, 4)
            topic := std.kafka.read_string(r*, 249)
            partitions := std.kafka.read_int(r*, 4)
            partition_id := std.kafka.read_int(r*, 4)
            batch := std.kafka.read_nullable(r*, 4, 1048576)
            if transaction.present || timeout < 1 || topics != 1 || topic != "topic" || partitions != 1 || partition_id != 0 || !batch.present { return 10 }
            if std.kafka.finished(r*).code != 0 || std.kafka.validate_record_batch(batch.data).code != 0 { return 11 }
            if mode == "valid" && round == 1 {
                if acks != 0 { return 12 }
            } else {
                if acks == 0 { return 13 }
                if mode == "timeout" { std.time.sleep_ms(300); break }
                if mode == "eof" { break }
                if mode == "malformed" {
                    if send_body(socket*, correlation, "x") != 0 { return 14 }
                    break
                }
                body := std.kafka.new_writer(100)
                std.kafka.put_int(body*, 1, 4)
                std.kafka.put_string(body*, "topic")
                std.kafka.put_int(body*, 1, 4)
                std.kafka.put_int(body*, 0, 4)
                status := 0
                if mode == "broker-error" && round == 1 { status = 6 }
                std.kafka.put_int(body*, status, 2)
                std.kafka.put_int(body*, 42, 8)
                std.kafka.put_int(body*, -1, 8)
                std.kafka.put_int(body*, 0, 4)
                if send_body(socket*, correlation, body.data) != 0 { return 15 }
            }
        }
        round = round + 1
    }
    std.tcp.close(socket*)
    return 0
}
