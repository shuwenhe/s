package main
func main() int {
    valid := parse_user("{\"name\":\"张三😀\",\"email\":\"x@example.test\",\"age\":null}")
    if !valid.valid || valid.name != "张三😀" || !std.database.is_null(valid.age) { return 1 }
    numeric := parse_user("{\"name\":\"李四\",\"email\":\"x@example.test\",\"age\":37}")
    if !numeric.valid { return 2 }
    age,error := std.database.as_integer(numeric.age)
    if error.code != 0 || age != 37 { return 3 }
    if parse_user("{\"name\":\"x\",\"email\":\"x@y\",\"unknown\":1}").valid { return 4 }
    if parse_user("{\"name\":\"x\",\"email\":\"x@y\",\"age\":1.2}").valid { return 5 }
    if parse_user("{\"name\":\"x\",\"email\":\"x@y\",\"age\":151}").valid { return 6 }
    if parse_user("{\"name\":\"x\",\"email\":\"x@y\",\"age\":-1}").valid { return 7 }
    if parse_user("{\"name\":\"x\",\"email\":\"x@y\",\"age\":\"37\"}").valid { return 8 }
    if parse_user("{\"name\":\"x\",\"email\":\"bad\"}").valid { return 9 }
    if parse_user("[]").valid { return 10 }
    return 0
}
