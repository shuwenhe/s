package main
import ("std.time"; "std.terminal"; "std.input"; "std.prelude")
extern "intrinsic" func host_args() string[]

// Board cells are y * 20 + x. Body is head first; arrays use S value semantics.
struct game { int[] body, int direction, int food, int seed, bool alive, bool won, int removed, int score }
func occupied(int[] body, int cell) bool {
    index := 0
    while index < len(body) {
        if body[index] == cell { return true }
        index = index + 1
    }
    return false
}
func place_food(game* state) {
    if len(state.body) == 240 { state.food = -1; state.won = true; return }
    state.seed = (state.seed * 1103515245 + 12345) & 2147483647
    candidate := state.seed % 240
    while occupied(state.body, candidate) { candidate = (candidate + 1) % 240 }
    state.food = candidate
}
func new_game() game {
    state := game { body: int[]{125,124,123}, direction: 0, food: -1, seed: 7, alive: true, won: false, removed: -1, score: 0 }
    place_food(state*)
    return state
}
func turn(int current, string kind) int {
    next := current
    if kind == "right" { next = 0 }
    if kind == "down" { next = 1 }
    if kind == "left" { next = 2 }
    if kind == "up" { next = 3 }
    if (next + 2) % 4 == current { return current }
    return next
}
func advance(game* state) {
    if !state.alive || state.won { return }
    head := state.body[0]
    x := head % 20
    y := head / 20
    if state.direction == 0 { x = x + 1 }
    if state.direction == 1 { y = y + 1 }
    if state.direction == 2 { x = x - 1 }
    if state.direction == 3 { y = y - 1 }
    if x < 0 || x >= 20 || y < 0 || y >= 12 { state.alive = false; return }
    cell := y * 20 + x
    growing := cell == state.food
    keep := len(state.body) - 1
    if growing { keep = len(state.body) }
    index := 0
    while index < keep {
        if state.body[index] == cell { state.alive = false; return }
        index = index + 1
    }
    state.removed = -1
    if !growing { state.removed = state.body[len(state.body) - 1] }
    body := int[]{cell}
    index = 0
    while index < keep { body = append(body, state.body[index]); index = index + 1 }
    state.body = body
    if growing { state.score = state.score + 1; place_food(state*) }
}
func rules_test() int {
    state := new_game()
    duplicate := new_game()
    if state.food != duplicate.food || occupied(state.body, state.food) { return 51 }
    if turn(0, "left") != 0 || turn(0, "up") != 3 { return 52 }
    state.food = 126
    advance(state*)
    if len(state.body) != 4 || state.body[0] != 126 || state.score != 1 || occupied(state.body, state.food) { return 53 }
    state.body = int[]{0,1,2}; state.direction = 2
    advance(state*)
    if state.alive { return 54 }
    state = new_game()
    state.body = int[]{21,22,42,41}; state.direction = 1; state.food = 100
    advance(state*)
    if !state.alive || state.body[0] != 41 || len(state.body) != 4 { return 55 }
    state.body = int[]{21,22,42,41,40}; state.direction = 1
    advance(state*)
    if state.alive { return 56 }
    state = new_game()
    state.body = int[]()
    index := 0
    while index < 240 { state.body = append(state.body, index); index = index + 1 }
    place_food(state*)
    if !state.won || state.food != -1 { return 57 }
    println("snake rules: PASS")
    return 0
}
func draw_at(std.terminal.output_buffer* output, int row, int column, string text) int {
    position, error := std.terminal.cursor_position(row, column)
    if error.code != 0 { return error.code }
    sequence := position + text
    return std.terminal.buffer_append(output*, sequence).code
}
func draw_cell(std.terminal.output_buffer* output, int cell, string text) int {
    if cell < 0 { return 0 }
    return draw_at(output*, cell / 20 + 2, cell % 20 + 2, text)
}
func initial_scene(std.terminal.output_buffer* output, game state) int {
    row := 1
    while row <= 14 {
        line := "#                    #"
        if row == 1 || row == 14 { line = "######################" }
        status := draw_at(output*, row, 1, line)
        if status != 0 { return status }
        row = row + 1
    }
    status := draw_at(output*, 16, 1, "WASD / arrows; q / ESC / Ctrl-C: quit")
    if status != 0 { return status }
    index := 0
    while index < len(state.body) {
        status = draw_cell(output*, state.body[index], "o")
        if status != 0 { return status }
        index = index + 1
    }
    status = draw_cell(output*, state.food, "*")
    if status != 0 { return status }
    return std.terminal.flush(output*).code
}
func play(std.terminal.output_buffer* output, std.input.reader* keyboard) int {
    state := new_game()
    status := initial_scene(output*, state)
    if status != 0 { return status }
    clock, clock_error := std.time.timer_start()
    if clock_error.code != 0 { return clock_error.code }
    changed := false
    while state.alive && !state.won {
        event, input_error := std.input.read_nonblocking(keyboard*)
        if input_error.code != 0 { return input_error.code }
        if event.kind == "eof" || event.kind == "escape" || event.code == 113 || event.code == 81 || event.code == 3 { return 0 }
        if !changed {
            next := turn(state.direction, event.kind)
            if next != state.direction { state.direction = next; changed = true }
        }
        elapsed, time_error := std.time.elapsed_time(clock)
        if time_error.code != 0 { return time_error.code }
        if elapsed.nanoseconds >= 100000000 {
            old_head := state.body[0]
            old_food := state.food
            advance(state*)
            if !state.alive { break }
            status = draw_cell(output*, state.removed, " ")
            if status == 0 { status = draw_cell(output*, old_head, "o") }
            if status == 0 { status = draw_cell(output*, state.body[0], "O") }
            if status == 0 && old_food != state.food { status = draw_cell(output*, state.food, "*") }
            score := "Score: " + std.prelude.to_string(state.score)
            if status == 0 { status = draw_at(output*, 15, 1, score) }
            if status == 0 { status = std.terminal.flush(output*).code }
            if status != 0 { return status }
            time_error = std.time.timer_reset(clock*)
            if time_error.code != 0 { return time_error.code }
            changed = false
        }
        sleep_error := std.time.sleep_ms(10)
        if sleep_error.code != 0 { return sleep_error.code }
    }
    return 0
}
func main() int {
    args := host_args()
    if len(args) > 1 && args[1] == "--self-test" { return rules_test() }
    size, size_error := std.terminal.dimensions(1)
    if size_error.code != 0 { return size_error.code }
    if size.rows < 16 || size.columns < 38 { return 22 }
    raw, raw_error := std.input.raw_mode(0)
    if raw_error.code != 0 { return raw_error.code }
    screen, screen_error := std.terminal.initialize(1)
    if screen_error.code != 0 {
        ignored := std.input.restore(raw*)
        return screen_error.code
    }
    output, output_error := std.terminal.new_buffer(1, 4096)
    keyboard, keyboard_error := std.input.new_reader(0)
    status := output_error.code
    if status == 0 { status = keyboard_error.code }
    if status == 0 { status = play(output*, keyboard*) }
    raw_error = std.input.restore(raw*)
    screen_error = std.terminal.restore(screen*)
    if status == 0 { status = raw_error.code }
    if status == 0 { status = screen_error.code }
    return status
}
