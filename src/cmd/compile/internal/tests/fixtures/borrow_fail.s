package demo.borrow

func bad(int value, string text) string {
    let shared = &value
    let unique = &mut value
    let moved = text
    text
}
