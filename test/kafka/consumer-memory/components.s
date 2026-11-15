package main
import ("std.kafka"; "std.tcp"; "std.time"; "std.prelude")
extern "intrinsic" func host_args() string[]
func mark(string phase) { println("phase=" + phase); std.time.sleep_ms(200); return }
func main() int {
    args := host_args()
    if len(args) != 2 { return 99 }
    mode := args[1]
    chunk := "x"
    i := 0
    while i < 10 { chunk = chunk + chunk; i = i + 1 }
    payload := chunk
    i = 0
    while i < 9 { payload = payload + payload; i = i + 1 }
    ints := int[]()
    i = 0
    while i < 1024 { ints = append(ints, 120); i = i + 1 }
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { value: std.kafka.bytes(payload), timestamp_ms: 0 })
    encoded, encode_error := std.kafka.encode_record_batch(records)
    if encode_error.code != 0 { return 1 }
    mark("ready")
    round := 0
    while round < 16 {
        if mode == "decode" {
            decoder := std.kafka.consumer_decoder_new(encoded, 0, 0, false)
            while decoder.stage != 4 && decoder.problem.code == 0 { std.kafka.consumer_decoder_step(decoder*) }
            if decoder.problem.code != 0 || len(decoder.output.records) != 1 || decoder.output.records[0].value.data != payload { return 2 }
        } else {
            link := std.kafka.consumer_link {}
            i = 0
            while i < 512 {
                part := chunk
                if mode == "tcp-bytes" { part = std.tcp._bytes(ints, 0, 1024) }
                std.kafka._kc_body_append(link*, part)
                i = i + 1
            }
            collected := std.kafka._kc_body_collect(link.body_fragments)
            if collected != payload { return 3 }
        }
        round = round + 1
        if round == 1 || round == 16 { mark("round-" + std.prelude.to_string(round)) }
    }
    mark("done")
    std.time.sleep_ms(500)
    return 0
}
