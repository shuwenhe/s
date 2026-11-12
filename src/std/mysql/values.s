package std.mysql
import "std.database"

func _type_name(int type_id) string {
    if type_id == 1 || type_id == 2 || type_id == 3 || type_id == 8 || type_id == 9 || type_id == 13 { return "integer" }
    if type_id == 0 || type_id == 246 { return "decimal" }
    if type_id == 4 || type_id == 5 { return "floating" }
    if type_id == 7 || type_id == 12 { return "timestamp" }
    if type_id == 10 { return "date" }
    if type_id == 11 { return "time" }
    if type_id == 245 { return "json" }
    return "string"
}
func _text_value(string text, column_definition column) (std.database.value,std.database.error) {
    kind := _type_name(column.type_id)
    if kind == "integer" {
        if (column.flags & 32) != 0 { return std.database.unsigned_value(text) }
        number,error := std.database.parse_integer(text)
        return std.database.value.integer(number),error
    }
    if kind == "decimal" { return std.database.decimal_value(text) }
    if kind == "floating" { return std.database.value.floating(text),std.database.error {} }
    if kind == "timestamp" { return std.database.value.timestamp(text),std.database.error {} }
    if kind == "date" { return std.database.value.date(text),std.database.error {} }
    if kind == "time" { return std.database.value.time(text),std.database.error {} }
    if kind == "json" { return std.database.value.json(text),std.database.error {} }
    if column.charset == 63 || column.type_id == 16 { return std.database.value.binary(text),std.database.error {} }
    return std.database.value.text(text),std.database.error {}
}
