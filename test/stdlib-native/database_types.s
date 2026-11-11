package main
import ("std.database"; "std.option")
func main() int {
    if !std.database.is_null(std.database.value.null) { return 1 }
    if std.database.is_null(std.database.value.text("")) { return 2 }
    if std.database.is_null(std.database.value.binary("")) { return 3 }
    if std.database.is_null(std.database.value.boolean(false)) { return 4 }
    integer, error := std.database.parse_integer("-9223372036854775808")
    if error.code != 0 || integer != -9223372036854775808 { return 5 }
    maximum, max_error := std.database.parse_integer("9223372036854775807")
    if max_error.code != 0 || maximum != 9223372036854775807 { return 6 }
    ignored, overflow := std.database.parse_integer("9223372036854775808")
    if overflow.code != std.database.error_overflow { return 7 }
    ignored_negative, negative_overflow := std.database.parse_integer("-9223372036854775809")
    if negative_overflow.code != std.database.error_overflow { return 8 }
    empty, empty_error := std.database.parse_integer("")
    sign, sign_error := std.database.parse_integer("-")
    junk, junk_error := std.database.parse_integer("12x")
    if empty_error.code == 0 || sign_error.code == 0 || junk_error.code == 0 { return 9 }
    big, big_error := std.database.unsigned_value("18446744073709551615")
    if big_error.code != 0 { return 10 }
    switch big {
        std.database.value::unsigned_integer(text) : { if text != "18446744073709551615" { return 11 } },
        _ : return 12,
    }
    too_big, too_big_error := std.database.unsigned_value("18446744073709551616")
    if too_big_error.code != std.database.error_overflow { return 13 }
    invalid_unsigned, invalid_error := std.database.unsigned_value("-1")
    if invalid_error.code == 0 { return 14 }
    number, number_error := std.database.decimal_value("-12345678901234567890.000001")
    if number_error.code != 0 { return 15 }
    switch number {
        std.database.value::decimal(text) : { if text != "-12345678901234567890.000001" { return 16 } },
        _ : return 17,
    }
    bad_decimal, decimal_error := std.database.decimal_value("1.2.3")
    if decimal_error.code == 0 { return 18 }
    actual, actual_error := std.database.as_integer(std.database.value.integer(0))
    if actual != 0 || actual_error.code != 0 { return 19 }
    null_integer, null_error := std.database.as_integer(std.database.value.null)
    text_integer, text_error := std.database.as_integer(std.database.value.text("42"))
    if null_error.code == 0 || text_error.code == 0 { return 20 }
    metadata := std.database.execution_result { affected_rows: option.some("0"), last_insert_id: option[string].none, warning_count: 2, command_tag: "UPDATE" }
    if !metadata.affected_rows.is_some() || metadata.affected_rows.unwrap() != "0" { return 21 }
    if !metadata.last_insert_id.is_none() { return 22 }
    println("database values: PASS")
    return 0
}
