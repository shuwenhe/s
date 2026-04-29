package compile.internal.liveness

use std.vec.vec

struct live_interval {
    int value_id
    int start
    int end
}

struct live_event {
    int point
    int value_id
    bool on
}

func build_live_intervals(vec[live_event] events) vec[live_interval] {
    let out = vec[live_interval]()
    let i = 0
    while i < events.len() {
        let ev = events[i]
        let idx = find_interval_index(out, ev.value_id)
        if ev.on {
            if idx < 0 {
                out.push(live_interval { value_id: ev.value_id, start: ev.point, end: ev.point })
            } else if ev.point < out[idx].start {
                out[idx].start = ev.point
            }
        } else {
            if idx >= 0 && ev.point > out[idx].end {
                out[idx].end = ev.point
            }
        }
        i = i + 1
    }
    out
}

func interval_length(live_interval iv) int {
    if iv.end < iv.start {
        return 0
    }
    iv.end - iv.start + 1
}

func intervals_overlap(live_interval a, live_interval b) bool {
    if a.end < b.start {
        return false
    }
    if b.end < a.start {
        return false
    }
    true
}

func merge_intervals(live_interval a, live_interval b) live_interval {
    let start = a.start
    if b.start < start {
        start = b.start
    }
    let end = a.end
    if b.end > end {
        end = b.end
    }
    live_interval { value_id: a.value_id, start: start, end: end }
}

func find_interval_index(vec[live_interval] ivs, int value_id) int {
    let i = 0
    while i < ivs.len() {
        if ivs[i].value_id == value_id {
            return i
        }
        i = i + 1
    }
    -1
}
