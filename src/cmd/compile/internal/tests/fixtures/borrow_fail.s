package demo.borrow

func bad(int value, string text) string {
    shared := &value
    unique := &value
    moved := text
    text
}
