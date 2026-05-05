package src.net

// S 语言伪协程/事件循环演示
// 实际 S 运行时需支持线程/调度，以下为接口演示

func go_spawn(func f) {
    // TODO: 运行 f 作为协程/线程
    f()
}

func event_loop() {
    // 伪事件循环，监听多个 fd
    []int fds = [3,4,5]
    while true {
        poll(fds, 1000) // 伪 poll
        // 处理事件
        for fd in fds {
            // TODO: 检查 fd 是否可读/写
            // go_spawn(func() { handle_fd(fd) })
        }
    }
}
