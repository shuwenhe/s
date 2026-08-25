package demo.borrow

func bad(int value, string text) string {
    shared := &value
    unique := &mut value
    moved := text
    text
}
