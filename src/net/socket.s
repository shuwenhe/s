// ============================================================
// socket.s — S 语言网络套接字高级封装
// 基于 src.syscall 提供面向使用者的 TCP/UDP 接口。
// ============================================================
package src.net

use src.syscall as sc
use std.result.result
use std.vec.vec
use std.option.option

// 重新导出常用常量
const AF_INET    = sc.AF_INET
const AF_INET6   = sc.AF_INET6
const SOCK_STREAM = sc.SOCK_STREAM
const SOCK_DGRAM  = sc.SOCK_DGRAM
const POLLIN      = sc.POLLIN
const POLLOUT     = sc.POLLOUT
const POLLERR     = sc.POLLERR

// ─── 错误类型（与 syscall 层共用）────────────────────────────
struct net_error {
    string message
    int    errno_code
}

func wrap_sc_err(sc.net_error e) net_error {
    net_error { message: e.message, errno_code: e.errno_code }
}

// ─── TCPListener ──────────────────────────────────────────────
struct TCPListener {
    int    fd
    string host
    int    port
}

// 创建 TCP 监听器，绑定并开始监听
func listen_tcp(string host, int port) result[TCPListener, net_error] {
    // 1. 创建套接字
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_STREAM, sc.IPPROTO_TCP)
    let fd = switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }

    // 2. SO_REUSEADDR
    switch sc.set_reuseaddr(fd) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    // 3. bind
    switch sc.bind(fd, host, port, sc.AF_INET) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    // 4. listen（backlog = 128）
    switch sc.listen(fd, 128) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    result::ok(TCPListener { fd: fd, host: host, port: port })
}

impl TCPListener {
    // 阻塞等待下一个连接
    func accept(self) result[TCPConn, net_error] {
        let res = sc.accept_addr(self.fd)
        switch res {
            result::ok(ar)  : result::ok(TCPConn {
                fd:        ar.fd,
                remote_ip: ar.ip,
                remote_port: ar.port,
            }),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 设为非阻塞模式（配合事件循环使用）
    func set_nonblocking(self) result[(), net_error] {
        switch sc.set_nonblocking(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 关闭监听器
    func close(self) result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }
}

// ─── TCPConn ──────────────────────────────────────────────────
struct TCPConn {
    int    fd
    string remote_ip
    int    remote_port
}

// 主动发起 TCP 连接
func dial_tcp(string host, int port) result[TCPConn, net_error] {
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_STREAM, sc.IPPROTO_TCP)
    let fd = switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }

    // TCP_NODELAY（减少延迟）
    sc.set_tcp_nodelay(fd)

    switch sc.connect(fd, host, port, sc.AF_INET) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    result::ok(TCPConn { fd: fd, remote_ip: host, remote_port: port })
}

impl TCPConn {
    // 读取最多 max_bytes 字节，返回字符串（按字节读）
    func read(self, int max_bytes) result[string, net_error] {
        switch sc.read_string(self.fd, max_bytes) {
            result::ok(data) : result::ok(data),
            result::err(e)   : result::err(wrap_sc_err(e)),
        }
    }

    // 写入字符串（按字节写），返回实际写入字节数
    func write(self, string data) result[int, net_error] {
        switch sc.write_string(self.fd, data) {
            result::ok(n)  : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 设为非阻塞
    func set_nonblocking(self) result[(), net_error] {
        switch sc.set_nonblocking(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 等待可读（timeout_ms < 0 = 永久等待）
    func wait_readable(self, int timeout_ms) result[bool, net_error] {
        switch sc.poll_ready(self.fd, sc.POLLIN, timeout_ms) {
            result::ok(n)  : result::ok(n > 0),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 等待可写
    func wait_writable(self, int timeout_ms) result[bool, net_error] {
        switch sc.poll_ready(self.fd, sc.POLLOUT, timeout_ms) {
            result::ok(n)  : result::ok(n > 0),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 关闭连接
    func close(self) result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }
}

// ─── I/O 事件循环（kqueue/epoll 封装）────────────────────────
struct Poller {
    int fd
}

func new_poller() result[Poller, net_error] {
    switch sc.poller_create() {
        result::ok(fd) : result::ok(Poller { fd: fd }),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

impl Poller {
    func add(self, int sock_fd, int events) result[(), net_error] {
        switch sc.poller_add(self.fd, sock_fd, events) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    func del(self, int sock_fd) result[(), net_error] {
        switch sc.poller_del(self.fd, sock_fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    // 返回就绪 fd 列表，timeout_ms < 0 = 永久阻塞
    func wait(self, int max, int timeout_ms) result[vec[int], net_error] {
        switch sc.poller_wait(self.fd, max, timeout_ms) {
            result::ok(fds) : result::ok(fds),
            result::err(e)  : result::err(wrap_sc_err(e)),
        }
    }

    func close(self) result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }
}

// ─── UDP Socket ──────────────────────────────────────────────
struct UDPConn {
    int    fd
    string local_ip
    int    local_port
}

func listen_udp(string host, int port) result[UDPConn, net_error] {
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_DGRAM, sc.IPPROTO_UDP)
    let fd = switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.bind(fd, host, port, sc.AF_INET) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(UDPConn { fd: fd, local_ip: host, local_port: port })
}

impl UDPConn {
    func read(self, int max_bytes) result[string, net_error] {
        switch sc.read_string(self.fd, max_bytes) {
            result::ok(data) : result::ok(data),
            result::err(e)   : result::err(wrap_sc_err(e)),
        }
    }

    func write(self, string data) result[int, net_error] {
        switch sc.write_string(self.fd, data) {
            result::ok(n)  : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

    func close(self) result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }
}
