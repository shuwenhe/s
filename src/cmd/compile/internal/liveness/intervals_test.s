package compile.internal.liveness

use std.vec.vec

func intervals_test_case_name() string {
    "liveness/intervals_test.s"
}

func intervals_test_case_pass() int {
    var events = vec[live_event]()
    events.push(live_event { point: 0, value_id: 1, on: true })
    events.push(live_event { point: 3, value_id: 1, on: false })
    events.push(live_event { point: 2, value_id: 2, on: true })
    events.push(live_event { point: 6, value_id: 2, on: false })

    var ivs = build_live_intervals(events)
    if ivs.len() != 2 {
        return 0
    }
    if interval_length(ivs[0]) <= 0 {
        return 0
    }
    if !intervals_overlap(ivs[0], ivs[1]) {
        return 0
    }
    1
}
