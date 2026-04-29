package compile.internal.base

use std.vec.vec

struct timestamp {
    int tick
    string label
    bool start
}

struct timing_event {
    int size
    string unit
}

struct timings {
    vec[timestamp] list
    vec[timing_event] events
}

let timer = timings {
    list: vec[timestamp](),
    events: vec[timing_event](),
}

func timing_tick() int {
    timer.list.len() + timer.events.len()
}

func timings_start(vec[string] labels) () {
    timer.list.push(timestamp {
        tick: timing_tick(),
        label: join_with_colon(labels),
        start: true,
    })
}

func timings_stop(vec[string] labels) () {
    timer.list.push(timestamp {
        tick: timing_tick(),
        label: join_with_colon(labels),
        start: false,
    })
}

func timings_add_event(int size, string unit) () {
    timer.events.push(timing_event {
        size: size,
        unit: unit,
    })
}

func timings_write(string prefix) string {
    let out = ""
    let i = 0
    while i < timer.list.len() {
        let phase = timer.list[i]
        out = out + prefix + phase.label + "\t" + (if phase.start { "start" } else { "stop" }) + "\n"
        i = i + 1
    }
    i = 0
    while i < timer.events.len() {
        out = out + prefix + "event\t" + to_string(timer.events[i].size) + " " + timer.events[i].unit + "\n"
        i = i + 1
    }
    out
}

func join_with_colon(vec[string] labels) string {
    if labels.len() == 0 {
        return ""
    }
    let out = labels[0]
    let i = 1
    while i < labels.len() {
        out = out + ":" + labels[i]
        i = i + 1
    }
    out
}
