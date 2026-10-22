package main
struct inner { int number; string error }
struct outer { inner lex; int marker }
func advance(outer initial) outer {
    state := initial
    state.lex.number = state.lex.number + 1
    return state
}
func main() int {
    initial := outer { lex: inner { number: 40, error: "" }, marker: 9 }
    result := advance(initial)
    if result.lex.error != "" { return 1 }
    if result.lex.number != 41 { return 2 }
    if initial.lex.number != 40 { return 3 }
    if result.marker != 9 { return 4 }
    return 42
}
