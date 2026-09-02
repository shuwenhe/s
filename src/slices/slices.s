package std.slices
func grow_capacity(int old_cap, int needed) int {
    if old_cap == 0 {
        return 4
    }
    if old_cap < 256 {
        return old_cap * 2
    }
    loop {
        old_cap = old_cap + old_cap / 4
        if old_cap >= needed {
            break
        }
    }
    old_cap
}

func copy[t](t[] dst, t[] src) int {
    copied := 0
    if len(src) > len(dst) {
        copied = len(dst)
    } else {
        copied = len(src)
    }
    if copied > 0 {
        for i in 0..copied {
            dst[i] = src[i]
        }
    }
    copied
}

func contains[t](t[] s, t value) bool {
    for i in 0..len(s) {
        if s[i] == value {
            return true
        }
    }
    false
}

func find[t](t[] s, t value) int {
    for i in 0..len(s) {
        if s[i] == value {
            return i
        }
    }
    -1
}

func clear[t](t[] s) t[] {
    s.len = 0
    s
}

func reverse[t](t[] s) t[] {
    if len(s) <= 1 {
        return s
    }
    left := 0
    right := len(s) - 1
    loop {
        if left >= right {
            break
        }
        temp := s[left]
        s[left] = s[right]
        s[right] = temp
        left = left + 1
        right = right - 1
    }
    s
}

func insert[t](t[] s, int idx, t value) (t[], string) {
    if idx < 0 || idx > len(s) {
        return s, "index out of range"
    }
    s = append(s, value)
    if idx < len(s) - 1 {
        for i := len(s) - 1; i > idx; i = i - 1 {
            s[i] = s[i - 1]
        }
    }
    s[idx] = value
    return s, ""
}

func remove[t](t[] s, int idx) (t[], string) {
    if idx < 0 || idx >= len(s) {
        return s, "index out of range"
    }
    if idx < len(s) - 1 {
        for i := idx; i < len(s) - 1; i = i + 1 {
            s[i] = s[i + 1]
        }
    }
    s.len = s.len - 1
    return s, ""
}

func remove_range[t](t[] s, int start, int end) (t[], string) {
    if start < 0 || end > len(s) || start > end {
        return s, "invalid range"
    }
    if start == end {
        return s, ""
    }
    removed_count := end - start
    for i := start; i < len(s) - removed_count; i = i + 1 {
        s[i] = s[i + removed_count]
    }
    s.len = s.len - removed_count
    return s, ""
}

func fill[t](t[] s, t value) t[] {
    for i in 0..len(s) {
        s[i] = value
    }
    s
}

func clone[t](t[] s) t[] {
    if len(s) == 0 {
        return t[]{}
    }
    new_slice := make(t[], len(s))
    copy(new_slice, s)
    new_slice
}

func slices_unit_name() string {
    "std.slices"
}

func slices_unit_ready() int {
    1
}
