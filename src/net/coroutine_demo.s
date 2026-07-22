package src.net

use src.runtime as rt
use std.io as io
use std.vec.vec
use std.result.result

func run_echo_server(int port) result[(), net_error] {
    let listener_res = listen_tcp("0.0.0.0", port)
    let listener = switch listener_res {
        result::ok(l)  : l,
        result::err(e) : return result::err(e),
    }

    io.println("echo server listening on :" + rt.int_to_string(port))

    while true {
        let conn_res = listener.accept()
        switch conn_res {
            result::ok(conn) : {
                rt.goroutine_spawn(func() {
                    handle_echo_conn(conn)
                }, "echo-worker")
            },
            result::err(e) : {
                io.eprintln("accept error: " + e.message)
            },
        }
    }

    result::ok(())
}

func handle_echo_conn(TCPConn conn) () {
    let buf_size = 4096
    while true {
        let read_res = conn.read(buf_size)
        switch read_res {
            result::ok(data) : {
                if data == "" {
                    break
                }
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

func run_worker_pool(int num_workers, int num_tasks) () {
    let task_ch = rt.new_raw_chan(num_workers)
    let done_ch = rt.new_raw_chan(num_tasks)

    let i = 0
    while i < num_workers {
        let worker_id = i
        rt.goroutine_spawn(func() {
            worker_loop(task_ch, done_ch, worker_id)
        }, "worker-" + rt.int_to_string(worker_id))
        i = i + 1
    }

    let j = 0
    while j < num_tasks {
        rt.chan_send(task_ch, j)
        j = j + 1
    }

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
            break
        }
        io.println("worker " + rt.int_to_string(id) +
                   " processed task " + rt.int_to_string(task.value))
        rt.chan_send(done_ch, task.value)
    }
}

func run_select_demo() () {
    let ch1 = rt.new_raw_chan(1)
    let ch2 = rt.new_raw_chan(1)

    rt.chan_send(ch1, 42)
    rt.chan_send(ch2, 99)

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
