package std.mysql
import ("std.database"; "std.database.wire"; "std.prelude")

func _pad(int number, int width) string {
    text := std.prelude.to_string(number)
    while len(text) < width { text = "0" + text }
    return text
}
func _binary_integer(std.database.wire.cursor* source, int width, bool unsigned) (std.database.value,std.database.error) {
    bytes := std.database.wire.read_bytes(source*,width)
    if source.code != 0 { return std.database.value.null,protocol_error("truncated MySQL binary integer") }
    cursor := std.database.wire.cursor { data: bytes }
    if unsigned {
        text := std.database.wire.read_uint_decimal(cursor*,width,true)
        return std.database.unsigned_value(text)
    }
    number := 0
    if (std.database._byte(bytes,width - 1) & 128) != 0 { number = -1 }
    index := width
    while index > 0 {
        index = index - 1
        number = number * 256 + std.database._byte(bytes,index)
    }
    return std.database.value.integer(number),std.database.error {}
}
func _binary_temporal(std.database.wire.cursor* source, int type_id, int decimals) (std.database.value,std.database.error) {
    if decimals < 0 || decimals > 6 { return std.database.value.null,protocol_error("invalid MySQL temporal precision") }
    size := std.database.wire.read_byte(source*)
    if type_id == 11 {
        if size != 0 && size != 8 && size != 12 { return std.database.value.null,protocol_error("invalid MySQL binary time length") }
        negative := 0
        days := 0
        hours := 0
        minutes := 0
        seconds := 0
        fraction := 0
        if size > 0 {
            negative = std.database.wire.read_byte(source*)
            days = std.database.wire.read_uint(source*,4,true)
            hours = std.database.wire.read_byte(source*)
            minutes = std.database.wire.read_byte(source*)
            seconds = std.database.wire.read_byte(source*)
        }
        if size == 12 { fraction = std.database.wire.read_uint(source*,4,true) }
        if source.code != 0 || negative > 1 || hours > 23 || minutes > 59 || seconds > 59 || fraction > 999999 { return std.database.value.null,protocol_error("invalid MySQL binary time") }
        text := _pad(days * 24 + hours,2) + ":" + _pad(minutes,2) + ":" + _pad(seconds,2)
        if negative == 1 { text = "-" + text }
        if decimals > 0 { text = text + "." + std.database._slice(_pad(fraction,6),0,decimals) }
        return std.database.value.time(text),std.database.error {}
    }
    if size != 0 && size != 4 && size != 7 && size != 11 { return std.database.value.null,protocol_error("invalid MySQL binary date length") }
    if type_id == 10 && size != 0 && size != 4 { return std.database.value.null,protocol_error("invalid MySQL DATE length") }
    year := 0
    month := 0
    day := 0
    hour := 0
    minute := 0
    second := 0
    fraction := 0
    if size > 0 {
        year = std.database.wire.read_uint(source*,2,true)
        month = std.database.wire.read_byte(source*)
        day = std.database.wire.read_byte(source*)
    }
    if size >= 7 {
        hour = std.database.wire.read_byte(source*)
        minute = std.database.wire.read_byte(source*)
        second = std.database.wire.read_byte(source*)
    }
    if size == 11 { fraction = std.database.wire.read_uint(source*,4,true) }
    if source.code != 0 || year > 9999 || month > 12 || day > 31 || hour > 23 || minute > 59 || second > 59 || fraction > 999999 { return std.database.value.null,protocol_error("invalid MySQL binary date") }
    text := _pad(year,4) + "-" + _pad(month,2) + "-" + _pad(day,2)
    if type_id == 10 { return std.database.value.date(text),std.database.error {} }
    text = text + " " + _pad(hour,2) + ":" + _pad(minute,2) + ":" + _pad(second,2)
    if decimals > 0 { text = text + "." + std.database._slice(_pad(fraction,6),0,decimals) }
    return std.database.value.timestamp(text),std.database.error {}
}
func _binary_value(std.database.wire.cursor* source, column_definition column) (std.database.value,std.database.error) {
    width := 0
    if column.type_id == 1 { width = 1 }
    if column.type_id == 2 || column.type_id == 13 { width = 2 }
    if column.type_id == 3 || column.type_id == 9 { width = 4 }
    if column.type_id == 8 { width = 8 }
    if width > 0 {
        unsigned := (column.flags & 32) != 0
        return _binary_integer(source*,width,unsigned)
    }
    if column.type_id == 7 || column.type_id == 10 || column.type_id == 11 || column.type_id == 12 {
        type_id := column.type_id
        decimals := column.decimals
        return _binary_temporal(source*,type_id,decimals)
    }
    if column.type_id == 4 || column.type_id == 5 { return std.database.value.null,std.database.failure(std.database.error_unsupported,"binary FLOAT/DOUBLE conversion is not supported; CAST to DECIMAL or CHAR") }
    field := read_field(source*)
    if source.code != 0 || field.is_none() { return std.database.value.null,protocol_error("invalid MySQL binary string") }
    text := field.unwrap()
    return _text_value(text,column)
}
func _typed_binary_row(string payload, column_definition[] definitions) (std.database.row,std.database.error) {
    source := std.database.wire.cursor { data: payload }
    header := std.database.wire.read_byte(source*)
    size := (len(definitions) + 9) / 8
    bitmap := std.database.wire.read_bytes(source*,size)
    if source.code != 0 || header != 0 { return std.database.row {},protocol_error("invalid MySQL binary row header") }
    values := std.database.value[]()
    index := 0
    while index < len(definitions) {
        bit := index + 2
        null := (std.database._byte(bitmap,bit / 8) & (1 << (bit % 8))) != 0
        value := std.database.value.null
        if !null {
            definition := definitions[index]
            converted,error := _binary_value(source*,definition)
            if error.code != 0 { return std.database.row {},error }
            value = converted
        }
        values = append(values,value)
        index = index + 1
    }
    if source.position != len(payload) { return std.database.row {},protocol_error("extra MySQL binary row bytes") }
    return std.database.row { values: values },std.database.error {}
}
