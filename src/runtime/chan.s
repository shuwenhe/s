// ============================================================
// chan.s — S 运行时 Channel 实现
//
// 支持：
//   • 无缓冲 channel（cap == 0）：发送方/接收方必须同时就绪
//   • 有缓冲 channel（cap > 0）：ring buffer，满则阻塞发送，
//     空则阻塞接收
//   • close：标记关闭，接收方可排空缓冲后得到零值
//   • select（多路复用）：通过 try_send / try_recv 实现
//
// 并发安全：每个 Chan 持有一个 Mutex
// ============================================================
package src.runtime

use std.vec.vec
use std.result.result
use std.option.option

// ─── Channel 状态 ─────────────────────────────────────────────
const CHAN_OPEN   = 0
const CHAN_CLOSED = 1

// ─── 等待者记录 ───────────────────────────────────────────────
struct Waiter {
    int g_id      // 等待的 goroutine ID
    int val_idx   // 要传递的值在外部临时存储中的 index（-1 = 无）
}

// ─── 通用 Channel 结构（类型擦除，使用 int 承载值）────────────
// 注意：S 泛型暂不支持在运行时动态分配，使用 int 承载
//       类型安全由上层泛型包装确保
struct RawChan {
    int      cap        // 缓冲区容量（0 = 无缓冲）
    vec[int] buf        // 环形缓冲区
    int      head       // 下一个读位置
    int      tail       // 下一个写位置
    int      count      // 当前缓冲元素个数
    int      state      // CHAN_OPEN / CHAN_CLOSED
    vec[Waiter] senders   // 阻塞的发送者队列
    vec[Waiter] receivers // 阻塞的接收者队列
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

// ─── 阻塞发送 ─────────────────────────────────────────────────
func chan_send(RawChan mut ch, int val) result[(), string] {
    ch.mu.lock()

    // 不允许向已关闭的 channel 发送
    if ch.state == CHAN_CLOSED {
        ch.mu.unlock()
        return result::err("send on closed channel")
    }

    if ch.cap == 0 {
        // ── 无缓冲：找等待的接收者 ──
        if !ch.receivers.is_empty() {
            let recv_opt = dequeue_waiter(ch.receivers)
            ch.mu.unlock()
            switch recv_opt {
                option::some(w) : {
                    // 将值直接交给接收者（通过 goroutine 唤醒机制传递）
                    chan_deliver(w.g_id, val)
                    goready(w.g_id)
                },
                option::none : (),
            }
            return result::ok(())
        }
        // 无接收者：挂起自己
        let cur = __goroutine_current_id()
        ch.senders.push(Waiter { g_id: cur, val_idx: val })
        ch.mu.unlock()
        gopark(1)   // 1 = 等待 channel
        return result::ok(())
    }

    // ── 有缓冲：尝试入队 ──
    while ch.count >= ch.cap {
        // 缓冲满，挂起
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

    // 写入环形缓冲
    ch.buf.set(ch.tail, val)
    ch.tail = (ch.tail + 1) % ch.cap
    ch.count = ch.count + 1

    // 唤醒等待的接收者
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

// ─── 阻塞接收 ─────────────────────────────────────────────────
// 返回 (value, ok)：ok == false 表示 channel 已关闭且无数据
func chan_recv(RawChan mut ch) recv_result {
    ch.mu.lock()

    if ch.cap == 0 {
        // ── 无缓冲：找等待的发送者 ──
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
        // 挂起等待发送者
        let cur = __goroutine_current_id()
        ch.receivers.push(Waiter { g_id: cur, val_idx: -1 })
        ch.mu.unlock()
        gopark(1)
        let v = chan_take_delivered(cur)
        return recv_result { value: v, ok: true }
    }

    // ── 有缓冲：尝试出队 ──
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

    // 唤醒等待的发送者
    if !ch.senders.is_empty() {
        let send_opt = dequeue_waiter(ch.senders)
        ch.mu.unlock()
        switch send_opt {
            option::some(w) : {
                // 发送者携带的值已写入缓冲（val_idx = 值本身）
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

// ─── 非阻塞尝试发送（用于 select）────────────────────────────
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

// ─── 非阻塞尝试接收（用于 select）────────────────────────────
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

// ─── 关闭 channel ─────────────────────────────────────────────
func chan_close(RawChan mut ch) result[(), string] {
    ch.mu.lock()
    if ch.state == CHAN_CLOSED {
        ch.mu.unlock()
        return result::err("close of closed channel")
    }
    ch.state = CHAN_CLOSED

    // 唤醒所有阻塞的接收者（得到零值）
    while !ch.receivers.is_empty() {
        let w_opt = dequeue_waiter(ch.receivers)
        switch w_opt {
            option::some(w) : goready(w.g_id),
            option::none    : (),
        }
    }
    // 阻塞的发送者会 panic（close 后 send 是 panic）
    ch.mu.unlock()
    result::ok(())
}

// ─── 辅助：等待队列操作 ───────────────────────────────────────
func dequeue_waiter(vec[Waiter] mut q) option[Waiter] {
    if q.is_empty() {
        return option::none
    }
    let w = q.get(0).unwrap_or(Waiter { g_id: -1, val_idx: -1 })
    // 简化 dequeue：移除第一个元素（O(n)，生产中应用环形队列）
    let new_q = vec[Waiter]()
    let i = 1
    while i < q.len() {
        new_q.push(q.get(i).unwrap_or(Waiter { g_id: -1, val_idx: -1 }))
        i = i + 1
    }
    q = new_q
    option::some(w)
}

// ─── 值传递桥接（无缓冲 channel 直接交付）────────────────────
// 将值存入目标 goroutine 的"已投递值"槽位，
// 被唤醒后通过 chan_take_delivered 取出
extern "intrinsic" func __chan_deliver(int g_id, int val) ()
extern "intrinsic" func __chan_take_delivered(int g_id) int

func chan_deliver(int g_id, int val) () {
    __chan_deliver(g_id, val)
}

func chan_take_delivered(int g_id) int {
    __chan_take_delivered(g_id)
}

// ─── Channel 长度 / 容量查询 ─────────────────────────────────
func chan_len(RawChan ch) int  { ch.count }
func chan_cap(RawChan ch) int  { ch.cap   }

func chan_unit_name() string { "src/runtime/chan" }
func chan_unit_ready() int   { 1 }
