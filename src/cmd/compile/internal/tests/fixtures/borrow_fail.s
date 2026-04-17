package demo.borrow

func bad(int32 value, string text) string {
    var shared = &value
    var unique = &mut value
    var moved = text
    text
}
