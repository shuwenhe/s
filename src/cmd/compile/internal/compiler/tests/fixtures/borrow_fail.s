package demo.borrow

func bad(i32 value, String text) -> String {
    var shared = &value
    var unique = &mut value
    var moved = text
    text
}
