package compile.internal.base
use std.slices
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
    timestamp[] list
    timing_event[] events
}
timer := timings {
    list: timestamp[](), events timing_event[](),
}

func timing_tick() int {
    len(timer.list) + len(timer.events)
}

func timings_start(string[] labels) () {
    timer.list.push(timestamp {
        tick: timing_tick(), label join_with_colon(labels), start true,
    })
}

func timings_stop(string[] labels) () {
    timer.list.push(timestamp {
        tick: timing_tick(), label join_with_colon(labels), start false,
    })
}

func timings_add_event(int size, string unit) () {
    timer.events.push(timing_event {
        size: size, unit unit,
    })
}

func timings_write(string prefix) string {
    out := ""
    i := 0
    for i < len(timer.list) {
        phase := timer.list[i]
        out = out + prefix + phase.label + "\t" + (if phase.start { "start" } else { "stop" }) + "\n"
        i = i + 1
    }
    i = 0
    for i < len(timer.events) {
        out = out + prefix + "event\t" + to_string(timer.events[i].size) + " " + timer.events[i].unit + "\n"
        i = i + 1
    }
    out
}

func join_with_colon(string[] labels) string {
    if len(labels) == 0 {
        return ""
    }
    out := labels[0]
    i := 1
    for i < len(labels) {
        out = out + ":" + labels[i]
        i = i + 1
    }
    out
}
