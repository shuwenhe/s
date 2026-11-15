package main
import ("std.kafka"; "std.prelude")
func main() int {
    headers := std.kafka.header[]()
    headers = append(headers, std.kafka.header { key: std.kafka.byte_string(255), value: std.kafka.bytes("value") })
    records := std.kafka.message[]()
    records = append(records, std.kafka.message { value: std.kafka.bytes("value"), timestamp_ms: 0, headers: headers })
    encoded, encode_error := std.kafka.encode_record_batch(records)
    println("producer_encode_code=" + std.prelude.to_string(encode_error.code))
    validate_error := std.kafka.validate_record_batch(encoded)
    println("producer_validate_code=" + std.prelude.to_string(validate_error.code))
    decoded, decode_error := std.kafka.decode_record_batches(encoded, 0, 0)
    println("consumer_decode_code=" + std.prelude.to_string(decode_error.code))
    println(decode_error.message)
    if encode_error.code != 0 || validate_error.code != 0 || decode_error.code != std.kafka.error_protocol { return 1 }
    return 0
}
