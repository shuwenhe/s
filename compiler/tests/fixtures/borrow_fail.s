package demo.borrow

fn bad(value: i32, text: String) -> String {
    var shared = &value
    var unique = &mut value
    var moved = text
    text
}
