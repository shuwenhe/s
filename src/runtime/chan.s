package src.runtime

use std.vec.vec
use std.result.result
use std.option.option

const CHAN_OPEN   = 0
const CHAN_CLOSED = 1

struct Waiter {
    int g_id
    int val_idx
}

struct RawChan {
    int      cap
    vec[int] buf
    int      head
    int      tail
    int      count
    int      state
    vec[Waiter] senders
    vec[Waiter] receivers
    Mutex    mu
}

func new_raw_chan(int cap) RawChan {
    let buf = vec[int]()
    let i = 0
    while i < cap {
        buf.push(0)
        i = i + 1
    }
    RawChan {
        cap:       cap,
        buf:       buf,
        head:      0,
        tail:      0,
        count:     0,
        state:     CHAN_OPEN,
        senders:   vec[Waiter](),
        receivers: vec[Waiter](),
        mu:        new_mutex(),
    }
}

func chan_send(RawChan mut ch, int val) result[(), string] {
    ch.mu.lock()

    if ch.state == CHAN_CLOSED {
        ch.mu.unlock()
        return result::err("send on closed channel")
    }

    if ch.cap == 0 {
        if !ch.receivers.is_empty() {
            let recv_opt = dequeue_waiter(ch.receivers)
            ch.mu.unlock()
            switch recv_opt {
                option::some(w) : {
                    chan_deliver(w.g_id, val)
                    goready(w.g_id)
                },
                option::none : (),
            }
            return result::ok(())
        }
        let cur = __goroutine_current_id()
        ch.senders.push(Waiter { g_id: cur, val_idx: val })
        ch.mu.unlock()
        gopark(1)
        return result::ok(())
    }

    while ch.count >= ch.cap {
        let cur = __goroutine_current_id()
        ch.senders.push(Waiter { g_id: cur, val_idx: val })
        ch.mu.unlock()
        gopark(1)
        ch.mu.lock()
        if ch.state == CHAN_CLOSED {
            ch.mu.unlock()
            return result::err("send on closed channel")
        }
    }

    ch.buf.set(ch.tail, val)
    ch.tail = (ch.tail + 1) % ch.cap
    ch.count = ch.count + 1

    if !ch.receivers.is_empty() {
        let recv_opt = dequeue_waiter(ch.receivers)
        ch.mu.unlock()
        switch recv_opt {
            option::some(w) : goready(w.g_id),
            option::none    : (),
        }
        return result::ok(())
    }

    ch.mu.unlock()
    result::ok(())
}

func chan_recv(RawChan mut ch) recv_result {
    ch.mu.lock()

    if ch.cap == 0 {
        if !ch.senders.is_empty() {
            let send_opt = dequeue_waiter(ch.senders)
            ch.mu.unlock()
            switch send_opt {
                option::some(w) : {
                    goready(w.g_id)
                    return recv_result { value: w.val_idx, ok: true }
                },
                option::none : (),
            }
        }
        if ch.state == CHAN_CLOSED {
            ch.mu.unlock()
            return recv_result { value: 0, ok: false }
        }
        let cur = __goroutine_current_id()
        ch.receivers.push(Waiter { g_id: cur, val_idx: -1 })
        ch.mu.unlock()
        gopark(1)
        let v = chan_take_delivered(cur)
        return recv_result { value: v, ok: true }
    }

    while ch.count == 0 {
        if ch.state == CHAN_CLOSED {
            ch.mu.unlock()
            return recv_result { value: 0, ok: false }
        }
        let cur = __goroutine_current_id()
        ch.receivers.push(Waiter { g_id: cur, val_idx: -1 })
        ch.mu.unlock()
        gopark(1)
        ch.mu.lock()
    }

    let val = ch.buf.get(ch.head).unwrap_or(0)
    ch.head  = (ch.head + 1) % ch.cap
    ch.count = ch.count - 1

    if !ch.senders.is_empty() {
        let send_opt = dequeue_waiter(ch.senders)
        ch.mu.unlock()
        switch send_opt {
            option::some(w) : {
                ch.mu.lock()
                ch.buf.set(ch.tail, w.val_idx)
                ch.tail  = (ch.tail + 1) % ch.cap
                ch.count = ch.count + 1
                ch.mu.unlock()
                goready(w.g_id)
            },
            option::none : (),
        }
        return recv_result { value: val, ok: true }
    }

    ch.mu.unlock()
    recv_result { value: val, ok: true }
}

struct recv_result {
    int  value
    bool ok
}

func chan_try_send(RawChan mut ch, int val) bool {
    ch.mu.lock()
    if ch.state == CHAN_CLOSED {
        ch.mu.unlock()
        return false
    }
    if ch.cap == 0 {
        if !ch.receivers.is_empty() {
            let recv_opt = dequeue_waiter(ch.receivers)
            ch.mu.unlock()
            switch recv_opt {
                option::some(w) : {
                    chan_deliver(w.g_id, val)
                    goready(w.g_id)
                },
                option::none : (),
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

func chan_try_recv(RawChan mut ch) option[recv_result] {
    ch.mu.lock()
    if ch.cap == 0 {
        if !ch.senders.is_empty() {
            let send_opt = dequeue_waiter(ch.senders)
            ch.mu.unlock()
            switch send_opt {
                option::some(w) : {
                    goready(w.g_id)
                    return option::some(recv_result { value: w.val_idx, ok: true })
                },
                option::none : (),
            }
        }
        if ch.state == CHAN_CLOSED {
            ch.mu.unlock()
            return option::some(recv_result { value: 0, ok: false })
        }
        ch.mu.unlock()
        return option::none
    }
    if ch.count == 0 {
        if ch.state == CHAN_CLOSED {
            ch.mu.unlock()
            return option::some(recv_result { value: 0, ok: false })
        }
        ch.mu.unlock()
        return option::none
    }
    let val = ch.buf.get(ch.head).unwrap_or(0)
    ch.head  = (ch.head + 1) % ch.cap
    ch.count = ch.count - 1
    ch.mu.unlock()
    option::some(recv_result { value: val, ok: true })
}

func chan_close(RawChan mut ch) result[(), string] {
    ch.mu.lock()
    if ch.state == CHAN_CLOSED {
        ch.mu.unlock()
        return result::err("close of closed channel")
    }
    ch.state = CHAN_CLOSED

    while !ch.receivers.is_empty() {
        let w_opt = dequeue_waiter(ch.receivers)
        switch w_opt {
            option::some(w) : goready(w.g_id),
            option::none    : (),
        }
    }
    ch.mu.unlock()
    result::ok(())
}

func dequeue_waiter(vec[Waiter] mut q) option[Waiter] {
    if q.is_empty() {
        return option::none
    }
    let w = q.get(0).unwrap_or(Waiter { g_id: -1, val_idx: -1 })
    let new_q = vec[Waiter]()
    let i = 1
    while i < q.len() {
        new_q.push(q.get(i).unwrap_or(Waiter { g_id: -1, val_idx: -1 }))
        i = i + 1
    }
    q = new_q
    option::some(w)
}

extern "intrinsic" func __chan_deliver(int g_id, int val) ()
extern "intrinsic" func __chan_take_delivered(int g_id) int

func chan_deliver(int g_id, int val) () {
    __chan_deliver(g_id, val)
}

func chan_take_delivered(int g_id) int {
    __chan_take_delivered(g_id)
}

func chan_len(RawChan ch) int  { ch.count }
func chan_cap(RawChan ch) int  { ch.cap   }

func chan_unit_name() string { "src/runtime/chan" }
func chan_unit_ready() int   { 1 }
