// ============================================================
// coroutine_demo.s — S 语言并发网络服务器示例
//
// 演示：
//   1. 使用 goroutine_spawn 启动并发协程
//   2. 使用 TCPListener + Poller 构建事件驱动服务器
//   3. 使用 Channel 在协程间传递消息
//   4. 使用 Mutex 保护共享状态
// ============================================================
package src.net

use src.runtime as rt
use std.io as io
use std.vec.vec
use std.result.result

// ─── 示例 1：简单 echo 服务器 ────────────────────────────────
func run_echo_server(int port) result[(), net_error] {
    let listener_res = listen_tcp("0.0.0.0", port)
    let listener = switch listener_res {
        result::ok(l)  : l,
        result::err(e) : return result::err(e),
    }

    io.println("echo server listening on :" + rt.int_to_string(port))

    // 事件循环：每接收一个连接就启动新协程处理
    while true {
        let conn_res = listener.accept()
        switch conn_res {
            result::ok(conn) : {
                // goroutine_spawn 启动新协程，不阻塞 accept 循环
                rt.goroutine_spawn(func() {
                    handle_echo_conn(conn)
                }, "echo-worker")
            },
            result::err(e) : {
                io.eprintln("accept error: " + e.message)
                // 非致命错误，继续循环
            },
        }
    }

    result::ok(())
}

// 处理单个 echo 连接（在独立 goroutine 中运行）
func handle_echo_conn(TCPConn conn) () {
    let buf_size = 4096
    while true {
        let read_res = conn.read(buf_size)
        switch read_res {
            result::ok(data) : {
                if data == "" {
                    // 连接已关闭（EOF）
                    break
                }
                // 原样写回（echo）
                switch conn.write(data) {
                    result::ok(_)  : (),
                    result::err(e) : {
                        io.eprintln("write error: " + e.message)
                        break
                    },
                }
            },
            result::err(e) : {
                io.eprintln("read error: " + e.message)
                break
            },
        }
    }
    conn.close()
}

// ─── 示例 2：带 Channel 的并发任务分发 ──────────────────────
func run_worker_pool(int num_workers, int num_tasks) () {
    // 使用 RawChan 作为任务队列（缓冲 = num_workers）
    let task_ch = rt.new_raw_chan(num_workers)
    let done_ch = rt.new_raw_chan(num_tasks)

    // 启动 worker goroutine
    let i = 0
    while i < num_workers {
        let worker_id = i
        rt.goroutine_spawn(func() {
            worker_loop(task_ch, done_ch, worker_id)
        }, "worker-" + rt.int_to_string(worker_id))
        i = i + 1
    }

    // 分发任务
    let j = 0
    while j < num_tasks {
        rt.chan_send(task_ch, j)
        j = j + 1
    }

    // 收集完成信号
    let k = 0
    while k < num_tasks {
        let r = rt.chan_recv(done_ch)
        if !r.ok { break }
        k = k + 1
    }

    io.println("all tasks done")
}

func worker_loop(rt.RawChan mut task_ch, rt.RawChan mut done_ch, int id) () {
    while true {
        let task = rt.chan_recv(task_ch)
        if !task.ok {
            break  // channel 已关闭，退出
        }
        // 模拟任务处理
        io.println("worker " + rt.int_to_string(id) +
                   " processed task " + rt.int_to_string(task.value))
        rt.chan_send(done_ch, task.value)
    }
}

// ─── 示例 3：select 多路 channel ─────────────────────────────
func run_select_demo() () {
    let ch1 = rt.new_raw_chan(1)
    let ch2 = rt.new_raw_chan(1)

    // 向两个 channel 发送值
    rt.chan_send(ch1, 42)
    rt.chan_send(ch2, 99)

    // select：优先处理就绪的 channel
    let r1 = rt.chan_try_recv(ch1)
    let r2 = rt.chan_try_recv(ch2)

    switch r1 {
        option::some(res) : io.println("ch1 received: " + rt.int_to_string(res.value)),
        option::none      : (),
    }
    switch r2 {
        option::some(res) : io.println("ch2 received: " + rt.int_to_string(res.value)),
        option::none      : (),
    }
}
