package demo.borrow

fn bad(value: i32, text: String) -> String {
    let shared = &value
    let unique = &mut value
    let moved = text
    text
}
