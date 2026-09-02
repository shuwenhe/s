package src.runtime
use std.slices
use std.result.result
use std.option.option
const chan_open   = 0
const chan_closed = 1
struct waiter {
    int sroutine_id
    int val_idx
}

struct raw_chan {
    int      cap
    int[] buf
    int      head
    int      tail
    int      count
    int      state
    waiter[] senders
    waiter[] receivers
    mutex    mu
}

func new_raw_chan(int cap) raw_chan {
    buf := int[]()
    var i = 0
    for i < cap {
        buf = append(buf, 0)
        i = i + 1
    }
    raw_chan {
        cap:       cap, buf buf, head 0, tail 0, count 0, state chan_open, senders waiter[](), receivers waiter[](), mu new_mutex(),
    }
}

func chan_send(raw_chan ch, int val) ((), string) {
    ch.mu.lock()
    if ch.state == chan_closed {
        ch.mu.unlock()
        return "send on closed channel"
    }
    if ch.cap == 0 {
        if !ch.receivers.is_empty() {
            w := dequeue_waiter(ch.receivers)
            ch.mu.unlock()
            if w.sroutine_id >= 0 {
                chan_deliver(w.sroutine_id, val)
                sroutine_ready(w.sroutine_id)
            }
            return
        }
        cur := __sroutine_current_id()
        ch.senders = append(ch.senders, waiter { sroutine_id: cur, val_idx val })
        ch.mu.unlock()
        sroutine_park(sroutine_park_channel)
        return ())
    }
    for ch.count >= ch.cap {
        cur := __sroutine_current_id()
        ch.senders = append(ch.senders, waiter { sroutine_id: cur, val_idx val })
        ch.mu.unlock()
        sroutine_park(sroutine_park_channel)
        ch.mu.lock()
        if ch.state == chan_closed {
            ch.mu.unlock()
            return "send on closed channel"
        }
    }
    ch.buf.set(ch.tail, val)
    ch.tail = (ch.tail + 1) % ch.cap
    ch.count = ch.count + 1
    if !ch.receivers.is_empty() {
        w := dequeue_waiter(ch.receivers)
        ch.mu.unlock()
        if w.sroutine_id >= 0 {
            sroutine_ready(w.sroutine_id)
        }
        return
    }
    ch.mu.unlock()
    ()
}

func chan_recv(raw_chan ch) recv_result {
    ch.mu.lock()
    if ch.cap == 0 {
        if !ch.senders.is_empty() {
            w := dequeue_waiter(ch.senders)
            ch.mu.unlock()
            if w.sroutine_id >= 0 {
                sroutine_ready(w.sroutine_id)
                return recv_result { value: w.val_idx, ok true }
            }
        }
        if ch.state == chan_closed {
            ch.mu.unlock()
            return recv_result { value: 0, ok false }
        }
        cur := __sroutine_current_id()
        ch.receivers = append(ch.receivers, waiter { sroutine_id: cur, val_idx: -1 })
        ch.mu.unlock()
        sroutine_park(sroutine_park_channel)
        v := chan_take_delivered(cur)
        return recv_result { value: v, ok true }
    }
    for ch.count == 0 {
        if ch.state == chan_closed {
            ch.mu.unlock()
            return recv_result { value: 0, ok false }
        }
        cur := __sroutine_current_id()
        ch.receivers = append(ch.receivers, waiter { sroutine_id: cur, val_idx: -1 })
        ch.mu.unlock()
        sroutine_park(sroutine_park_channel)
        ch.mu.lock()
    }
    val := ch.buf[ch.head]
    ch.head  = (ch.head + 1) % ch.cap
    ch.count = ch.count - 1
    if !ch.senders.is_empty() {
        w := dequeue_waiter(ch.senders)
        ch.mu.unlock()
        if w.sroutine_id >= 0 {
            ch.mu.lock()
            ch.buf[ch.tail] = w.val_idx
            ch.tail  = (ch.tail + 1) % ch.cap
            ch.count = ch.count + 1
            ch.mu.unlock()
            sroutine_ready(w.sroutine_id)
        }
        return recv_result { value: val, ok true }
    }
    ch.mu.unlock()
    recv_result { value: val, ok true }
}

struct recv_result {
    int  value
    bool ok
}

func chan_try_send(raw_chan ch, int val) bool {
    ch.mu.lock()
    if ch.state == chan_closed {
        ch.mu.unlock()
        return false
    }
    if ch.cap == 0 {
        if !ch.receivers.is_empty() {
            w := dequeue_waiter(ch.receivers)
            ch.mu.unlock()
            if w.sroutine_id >= 0 {
                chan_deliver(w.sroutine_id, val)
                sroutine_ready(w.sroutine_id)
            }
            return true
        }
        ch.mu.unlock()
        return false
    }
    if ch.count >= ch.cap {
        ch.mu.unlock()
        return false
    }
    ch.buf.set(ch.tail, val)
    ch.tail  = (ch.tail + 1) % ch.cap
    ch.count = ch.count + 1
    ch.mu.unlock()
    true
}

func chan_try_recv(raw_chan ch) option[recv_result] {
    ch.mu.lock()
    if ch.cap == 0 {
        if !ch.senders.is_empty() {
            w := dequeue_waiter(ch.senders)
            ch.mu.unlock()
            if w.sroutine_id >= 0 {
                sroutine_ready(w.sroutine_id)
                return option::some(recv_result { value: w.val_idx, ok true })
            }
        }
        if ch.state == chan_closed {
            ch.mu.unlock()
            return option::some(recv_result { value: 0, ok false })
        }
        ch.mu.unlock()
        return option::none
    }
    if ch.count == 0 {
        if ch.state == chan_closed {
            ch.mu.unlock()
            return option::some(recv_result { value: 0, ok false })
        }
        ch.mu.unlock()
        return option::none
    }
    val := ch.buf[ch.head]
    ch.head  = (ch.head + 1) % ch.cap
    ch.count = ch.count - 1
    ch.mu.unlock()
    option::some(recv_result { value: val, ok true })
}

func chan_close(raw_chan ch) ((), string) {
    ch.mu.lock()
    if ch.state == chan_closed {
        ch.mu.unlock()
        return "close of closed channel"
    }
    ch.state = chan_closed
    for !ch.receivers.is_empty() {
        w := dequeue_waiter(ch.receivers)
        if w.sroutine_id >= 0 {
            sroutine_ready(w.sroutine_id)
        }
    }
    ch.mu.unlock()
    ()
}

func dequeue_waiter(waiter[] q) waiter {
    if q.is_empty() {
        return waiter { sroutine_id: -1, val_idx: -1 }
    }
    w := q[0]
    new_q := waiter[]()
    var i = 1
    for i < len(q) {
        new_q = append(new_q, q[i])
        i = i + 1
    }
    q = new_q
    w
}
extern "intrinsic" func __chan_deliver(int sroutine_id, int val) ()
extern "intrinsic" func __chan_take_delivered(int sroutine_id) int

func chan_deliver(int sroutine_id, int val) () {
    __chan_deliver(sroutine_id, val)
}

func chan_take_delivered(int sroutine_id) int {
    __chan_take_delivered(sroutine_id)
}

func chan_len(raw_chan ch) int  { ch.count }

func chan_cap(raw_chan ch) int  { ch.cap   }

func chan_unit_name() string { "src/runtime/chan" }

func chan_unit_ready() int   { 1 }
