package compile.internal.escape

func escape_count_token(string text, string token) int {
    if token == "" {
        return 0
    }
    total := 0
    i := 0
    for i <= len(text) - len(token) {
        if slice(text, i, i + len(token)) == token {
            total = total + 1
            i = i + len(token)
        } else {
            i = i + 1
        }
    }
    total
}

func escape_level_name(int level) string {
    "escape"
}
