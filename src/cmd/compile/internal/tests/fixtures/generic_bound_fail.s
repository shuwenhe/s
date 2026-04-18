package demo.generic

func require_copy[t: copy](t value) t {
    value
}

func bad(string text) string {
    require_copy(text)
}
