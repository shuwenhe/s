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
    if mode == "write-timeout" {
        std.time.sleep_ms(500)
        std.tcp.close(socket*)
        return 0
    }
    rounds := 1
    if mode == "valid" { rounds = 2 }
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
        name := std.kafka.read_nullable(r*, 2, 32767)
        if key != 18 || version != 0 || correlation != round + 1 || !name.present || name.data != "fault-test" { return 6 }
        if mode == "decode-timeout" {
            payload := "x"
            i := 0
            while i < 15 { payload = payload + payload; i = i + 1 }
            large := std.kafka.new_writer(65536)
            std.kafka.put_int(large*, 32772, 4)
            std.kafka.put_int(large*, correlation, 4)
            std.kafka.put_raw(large*, payload)
            count, write_error := std.tcp.write_all(socket*, large.data, 1000)
            if write_error.code != 0 { return 9 }
            break
        }
        if mode == "timeout" { std.time.sleep_ms(300); break }
        if mode == "eof-header" {
            std.tcp.write_all(socket*, "x", 1000)
            break
        }
        w := std.kafka.new_writer(1024)
        length := 16
        if mode == "negative" { length = -1 }
        if mode == "short" { length = 3 }
        if mode == "oversize" { length = 1048577 }
        std.kafka.put_int(w*, length, 4)
        if mode == "mismatch" { correlation = correlation + 1 }
        std.kafka.put_int(w*, correlation, 4)
        if mode != "eof-body" {
            std.kafka.put_int(w*, 0, 2)
            std.kafka.put_int(w*, 1, 4)
            std.kafka.put_int(w*, 18, 2)
            std.kafka.put_int(w*, 0, 2)
            std.kafka.put_int(w*, 4, 2)
        }
        if mode == "valid" || mode == "slow" {
            i := 0
            while i < len(w.data) {
                piece, slice_error := std.tcp.slice(w.data, i, i + 1)
                count, write_error := std.tcp.write_all(socket*, piece, 1000)
                if write_error.code != 0 {
                    if mode == "slow" { std.tcp.close(socket*); return 0 }
                    return 7
                }
                pause := 1
                if mode == "slow" { pause = 40 }
                std.time.sleep_ms(pause)
                i = i + 1
            }
        } else {
            count, write_error := std.tcp.write_all(socket*, w.data, 1000)
            if write_error.code != 0 { return 8 }
        }
        round = round + 1
    }
    std.tcp.close(socket*)
    return 0
}
