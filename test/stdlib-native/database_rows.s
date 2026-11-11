package main
import ("std.database"; "std.option"; "std.result")
func row_item(std.result.result[option[std.database.row],std.database.error] outcome) option[std.database.row] {
    return switch outcome {
        std.result.result::ok(item) : item,
        std.result.result::err(_) : { panic("unexpected row error") },
    }
}
func row_error(std.result.result[option[std.database.row],std.database.error] outcome) int {
    return switch outcome { std.result.result::ok(_) : 0, std.result.result::err(error) : error.code, }
}
func cell_item(std.result.result[std.database.value,std.database.error] outcome) std.database.value {
    return switch outcome {
        std.result.result::ok(item) : item,
        std.result.result::err(_) : { panic("unexpected cell error") },
    }
}
func cell_error(std.result.result[std.database.value,std.database.error] outcome) int {
    return switch outcome { std.result.result::ok(_) : 0, std.result.result::err(error) : error.code, }
}
func columns_error(std.result.result[std.database.column[],std.database.error] outcome) int {
    return switch outcome { std.result.result::ok(_) : 0, std.result.result::err(error) : error.code, }
}
func main() int {
    column := std.database.column { name: "value", type_name: "text", native_type: option[int].none, binary_format: false }
    columns := std.database.column[]{column}
    null_cell := std.database.value.null
    empty_cell := std.database.value.text("")
    null_row := std.database.row { values: std.database.value[]{null_cell} }
    empty_row := std.database.row { values: std.database.value[]{empty_cell} }
    data := std.database.row[]{null_row,empty_row}
    cursor, error := std.database.buffered_rows(columns,data)
    if error.code != 0 { return 1 }
    first := row_item(cursor.next())
    if first.is_none() { return 2 }
    first_row := first.unwrap()
    cell := cell_item(first_row.get(0))
    if !std.database.is_null(cell) { return 3 }
    if cell_error(first_row.get(-1)) != std.database.error_bounds || cell_error(first_row.get(1)) != std.database.error_bounds { return 4 }
    second := row_item(cursor.next())
    if second.is_none() { return 5 }
    second_row := second.unwrap()
    if std.database.is_null(cell_item(second_row.get(0))) { return 6 }
    if !row_item(cursor.next()).is_none() || !row_item(cursor.next()).is_none() { return 7 }
    close_error := cursor.close()
    close_again := cursor.close()
    if close_error.code != 0 || close_again.code != 0 || len(cursor.data) != 0 { return 8 }
    if row_error(cursor.next()) != std.database.error_closed { return 9 }
    if columns_error(cursor.columns()) != std.database.error_closed { return 10 }
    if !std.database.is_null(cell) { return 11 }
    bad_row := std.database.row { values: std.database.value[]() }
    broken, broken_error := std.database.buffered_rows(columns,std.database.row[]{bad_row})
    if broken_error.code != std.database.error_invalid { return 12 }
    println("database rows: PASS")
    return 0
}
