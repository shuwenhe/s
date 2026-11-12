package main
import ("std.mysql"; "std.database"; "std.database.wire")
func byte(int value) string { bytes,error := std.database.wire.encode_uint(value,1,true); return bytes }
func main() int {
    definitions := std.mysql.column_definition[]()
    column0 := std.mysql.column_definition { type_id: 8, flags: 0, charset: 0 }
    definitions = append(definitions,column0)
    column1 := std.mysql.column_definition { type_id: 8, flags: 32, charset: 0 }
    definitions = append(definitions,column1)
    column2 := std.mysql.column_definition { type_id: 246, flags: 0, charset: 0 }
    definitions = append(definitions,column2)
    column3 := std.mysql.column_definition { type_id: 252, flags: 0, charset: 63 }
    definitions = append(definitions,column3)
    column4 := std.mysql.column_definition { type_id: 12, flags: 0, charset: 0 }
    definitions = append(definitions,column4)
    column5 := std.mysql.column_definition { type_id: 3, flags: 0, charset: 0 }
    definitions = append(definitions,column5)
    column6 := std.mysql.column_definition { type_id: 253, flags: 0, charset: 45 }
    definitions = append(definitions,column6)
    payload := byte(0) + byte(128) + byte(0)
    payload = payload + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(0) + byte(128)
    index := 0
    while index < 8 { payload = payload + byte(255); index = index + 1 }
    payload = payload + byte(4) + "1.20" + byte(3) + "a" + byte(0) + "b"
    payload = payload + byte(7) + byte(234) + byte(7) + byte(11) + byte(12) + byte(12) + byte(34) + byte(56)
    payload = payload + byte(6) + "中文"
    row,error := std.mysql._typed_binary_row(payload,definitions)
    if error.code != 0 { println(error.message); return 1 }
    number,integer_error := std.database.as_integer(row.values[0])
    if integer_error.code != 0 || number != -9223372036854775808 { return 2 }
    switch row.values[1] { std.database.value::unsigned_integer(v) : { if v != "18446744073709551615" { return 3 } }, _ : { return 4 }, }
    switch row.values[2] { std.database.value::decimal(v) : { if v != "1.20" { return 5 } }, _ : { return 6 }, }
    switch row.values[3] { std.database.value::binary(v) : { if len(v) != 3 || std.database._byte(v,1) != 0 { return 7 } }, _ : { return 8 }, }
    switch row.values[4] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56" { return 9 } }, _ : { return 10 }, }
    if !std.database.is_null(row.values[5]) { return 11 }
    switch row.values[6] { std.database.value::text(v) : { if v != "中文" { return 12 } }, _ : { return 13 }, }
    truncated,te := std.mysql._typed_binary_row(byte(0),definitions)
    if te.code == 0 { return 14 }
    fractional := std.mysql.column_definition { type_id: 12, decimals: 3 }
    fractional_columns := std.mysql.column_definition[]{fractional}
    fractional_payload := byte(0) + byte(0) + byte(11) + byte(234) + byte(7) + byte(11) + byte(12) + byte(12) + byte(34) + byte(56) + byte(120) + byte(224) + byte(1) + byte(0)
    fraction_row,fe := std.mysql._typed_binary_row(fractional_payload,fractional_columns)
    if fe.code != 0 { return 15 }
    switch fraction_row.values[0] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56.123" { return 16 } }, _ : { return 17 }, }
    zero_payload := byte(0) + byte(0) + byte(7) + byte(234) + byte(7) + byte(11) + byte(12) + byte(12) + byte(34) + byte(56)
    zero_row,ze := std.mysql._typed_binary_row(zero_payload,fractional_columns)
    if ze.code != 0 { return 18 }
    switch zero_row.values[0] { std.database.value::timestamp(v) : { if v != "2026-11-12 12:34:56.000" { return 19 } }, _ : { return 20 }, }
    return 0
}
