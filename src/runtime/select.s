package src.runtime
use std.option.option

struct runtime_select_result {
    int index
    int value
    bool ok
}

const runtime_select_receive = 0
const runtime_select_send = 1

struct runtime_select_case {
    raw_chan channel
    int kind
    int value
}


func runtime_select_try(runtime_select_case[] cases) runtime_select_result {
    int i = 0
    for i < len(cases) {
        current := cases[i]
        if current.kind == runtime_select_receive {
            option[recv_result] received = chan_try_recv(current.channel)
            if received.is_some() {
                value := received.unwrap()
                return runtime_select_result { index: i, value: value.value, ok: value.ok }
            }
        } else {
            if chan_try_send(current.channel, current.value) {
                return runtime_select_result { index: i, value: current.value, ok: true }
            }
        }
        i = i + 1
    }
    runtime_select_result { index: -1, value: 0, ok: false }
}



func runtime_select_recv(raw_chan[] channels) runtime_select_result {
    int i = 0
    for i < len(channels) {
        option[recv_result] result = chan_try_recv(channels[i])
        if result.is_some() {
            value := result.unwrap()
            return runtime_select_result { index: i, value: value.value, ok: value.ok }
        }
        i = i + 1
    }
    runtime_select_result { index: -1, value: 0, ok: false }
}

func select_unit_name() string {
    "src/runtime/select"
}

func select_unit_ready() int {
    1
}
