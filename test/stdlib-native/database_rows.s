package main
import ("std.database"; "std.option"; "std.result")
func main() int {
    columns := std.database.column[]{std.database.column { name: "value", type_name: "text", native_type: option[int].none, binary_format: false }}
    data := std.database.row[]{std.database.row { values: std.database.value[]{std.database.value.null} }, std.database.row { values: std.database.value[]{std.database.value.text("")} }}
    cursor, error := std.database.buffered_rows(columns,data)
    if error.code != 0 { return 1 }
    first_result := cursor.next()
    if first_result.is_err() { return 2 }
    first := first_result.unwrap()
    if first.is_none() { return 3 }
    first_row := first.unwrap()
    cell_result := first_row.get(0)
    if cell_result.is_err() { return 4 }
    cell := cell_result.unwrap()
    if !std.database.is_null(cell) { return 5 }
    invalid := first_row.get(-1)
    beyond := first_row.get(1)
    if !invalid.is_err() || !beyond.is_err() { return 6 }
    if invalid.unwrap_err().code != std.database.error_bounds || beyond.unwrap_err().code != std.database.error_bounds { return 7 }
    second_result := cursor.next()
    if second_result.is_err() { return 8 }
    second := second_result.unwrap()
    if second.is_none() { return 9 }
    second_row := second.unwrap()
    text_result := second_row.get(0)
    if text_result.is_err() || std.database.is_null(text_result.unwrap()) { return 10 }
    exhausted := cursor.next()
    again := cursor.next()
    if exhausted.is_err() || again.is_err() { return 11 }
    if !exhausted.unwrap().is_none() || !again.unwrap().is_none() { return 12 }
    close_error := cursor.close()
    close_again := cursor.close()
    if close_error.code != 0 || close_again.code != 0 || len(cursor.data) != 0 { return 13 }
    closed_row := cursor.next()
    closed_columns := cursor.columns()
    if !closed_row.is_err() || !closed_columns.is_err() { return 14 }
    if closed_row.unwrap_err().code != std.database.error_closed || closed_columns.unwrap_err().code != std.database.error_closed { return 15 }
    if !std.database.is_null(cell) { return 16 }
    broken, broken_error := std.database.buffered_rows(columns,std.database.row[]{std.database.row { values: std.database.value[]() }})
    if broken_error.code != std.database.error_invalid { return 17 }
    println("database rows: PASS")
    return 0
}
