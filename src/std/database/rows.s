package std.database
import ("std.option"; "std.result")

// Owned buffered result. Passed arrays are transferred by contract, not borrowed
// from a mutable network buffer. Returned rows remain valid after cursor close.
struct rows { column[] column_data, row[] data, int position, bool closed }
func buffered_rows(column[] columns, row[] data) (rows,error) {
    index := 0
    while index < len(data) {
        if len(data[index].values) != len(columns) {
            return rows { closed: true }, failure(error_invalid,"row width differs from column metadata")
        }
        index = index + 1
    }
    return rows { column_data: columns, data: data, position: 0, closed: false }, error { code: 0 }
}
func (std.database.rows* self) next() std.result.result[option[row],error] {
    if self.closed { return std.result.result.err(failure(error_closed,"rows are closed")) }
    if self.position < 0 || self.position > len(self.data) { return std.result.result.err(failure(error_invalid,"invalid rows position")) }
    if self.position == len(self.data) { return std.result.result.ok(option[row].none) }
    item := self.data[self.position]
    self.position = self.position + 1
    return std.result.result.ok(option.some(item))
}
func (std.database.rows self) columns() std.result.result[column[],error] {
    if self.closed { return std.result.result.err(failure(error_closed,"rows are closed")) }
    return std.result.result.ok(self.column_data)
}
func (std.database.rows* self) close() error {
    self.closed = true
    self.data = row[]()
    self.column_data = column[]()
    self.position = 0
    return error { code: 0 }
}
