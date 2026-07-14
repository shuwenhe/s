// ============================================================
// syscall_unix.s — POSIX 系统调用绑定层
// 为 S 运行时提供套接字、文件描述符、轮询等 OS 接口。
// 通过 extern "intrinsic" 桥接到宿主 C 运行时/libc。
// ============================================================
package src.syscall

use std.result.result
use std.vec.vec

// ─── 错误类型 ────────────────────────────────────────────────
struct net_error {
    string message
    int    errno_code
}

// ─── 常量：地址族 ────────────────────────────────────────────
const AF_UNSPEC = 0
const AF_INET  = 2
const AF_INET6 = 10
const AF_UNIX  = 1

// ─── 常量：套接字类型 ─────────────────────────────────────────
const SOCK_STREAM    = 1
const SOCK_DGRAM     = 2
const SOCK_NONBLOCK  = 2048
const SOCK_CLOEXEC   = 524288

// ─── 常量：协议 ───────────────────────────────────────────────
const IPPROTO_TCP = 6
const IPPROTO_UDP = 17

// ─── 常量：setsockopt 层/选项 ─────────────────────────────────
const SOL_SOCKET   = 1
const SO_REUSEADDR = 2
const SO_REUSEPORT = 15
const SO_KEEPALIVE = 9
const TCP_NODELAY  = 1

// ─── 常量：fcntl ──────────────────────────────────────────────
const F_GETFL    = 3
const F_SETFL    = 4
const O_NONBLOCK = 2048

// ─── 常量：poll events ────────────────────────────────────────
const POLLIN   = 1
const POLLOUT  = 4
const POLLERR  = 8
const POLLHUP  = 16
const POLLNVAL = 32

const SHUT_RD   = 0
const SHUT_WR   = 1
const SHUT_RDWR = 2

// ─── 原始 OS 桥接（由宿主运行时/libc 实现）─────────────────────
extern "intrinsic" func __sys_socket(int domain, int typ, int proto) int
extern "intrinsic" func __sys_bind(int sockfd, string ip, int port, int family) int
extern "intrinsic" func __sys_listen(int sockfd, int backlog) int
extern "intrinsic" func __sys_accept(int sockfd) int
extern "intrinsic" func __sys_connect(int sockfd, string ip, int port, int family) int
extern "intrinsic" func __sys_connect_deadline(int sockfd, string host, int port, int family, int timeout_ms) int
extern "intrinsic" func __sys_resolve_ip(string host, int family) vec[string]
extern "intrinsic" func __sys_read(int fd, vec[int] mut buf, int n) int
extern "intrinsic" func __sys_write(int fd, vec[int] buf, int n) int
extern "intrinsic" func __sys_read_string(int fd, int n) string
extern "intrinsic" func __sys_write_string(int fd, string data) int
extern "intrinsic" func __sys_sendto_string(int fd, string data, string ip, int port, int family) int
extern "intrinsic" func __sys_recvfrom_string(int fd, int n) string
extern "intrinsic" func __sys_last_recvfrom_ip() string
extern "intrinsic" func __sys_last_recvfrom_port() int
extern "intrinsic" func __sys_close(int fd) int
extern "intrinsic" func __sys_poll(vec[int] fds, int nfds, int events, int timeout_ms) int
extern "intrinsic" func __sys_poll_ready(int fd, int events, int timeout_ms) int
extern "intrinsic" func __sys_fcntl(int fd, int cmd, int arg) int
extern "intrinsic" func __sys_setsockopt(int sockfd, int level, int optname, int val) int
extern "intrinsic" func __sys_getsockopt(int sockfd, int level, int optname) int
extern "intrinsic" func __sys_set_deadline_ms(int fd, int read_timeout_ms, int write_timeout_ms) int
extern "intrinsic" func __sys_shutdown(int fd, int how) int
extern "intrinsic" func __sys_local_ip(int fd) string
extern "intrinsic" func __sys_local_port(int fd) int
extern "intrinsic" func __sys_peer_ip(int fd) string
extern "intrinsic" func __sys_peer_port(int fd) int
extern "intrinsic" func __sys_errno() int
extern "intrinsic" func __sys_strerror(int errno_code) string
extern "intrinsic" func __sys_sendfile(int out_fd, int in_fd, int offset, int count) int
extern "intrinsic" func __sys_splice(int in_fd, int out_fd, int count) int
extern "intrinsic" func __sys_interface_addresses() vec[string]
extern "intrinsic" func __sys_open_read(string path) int

// kqueue / epoll I/O 事件通知（平台自适应）
extern "intrinsic" func __sys_poller_create() int
extern "intrinsic" func __sys_poller_add(int poller_fd, int fd, int events) int
extern "intrinsic" func __sys_poller_del(int poller_fd, int fd) int
extern "intrinsic" func __sys_poller_wait(int poller_fd, int max, int timeout_ms) vec[int]

// ─── 辅助：构建 net_error ─────────────────────────────────────
func make_net_error(string msg) net_error {
    let code = __sys_errno()
    net_error {
        message:    msg + ": " + __sys_strerror(code),
        errno_code: code,
    }
}

// ─── 公开 API：socket ─────────────────────────────────────────
func socket(int domain, int typ, int proto) result[int, net_error] {
    let fd = __sys_socket(domain, typ, proto)
    if fd < 0 {
        result::err(make_net_error("socket"))
    } else {
        result::ok(fd)
    }
}

// ─── 公开 API：bind ───────────────────────────────────────────
func bind(int sockfd, string ip, int port, int family) result[(), net_error] {
    let r = __sys_bind(sockfd, ip, port, family)
    if r < 0 {
        result::err(make_net_error("bind"))
    } else {
        result::ok(())
    }
}

// ─── 公开 API：listen ─────────────────────────────────────────
func listen(int sockfd, int backlog) result[(), net_error] {
    let r = __sys_listen(sockfd, backlog)
    if r < 0 {
        result::err(make_net_error("listen"))
    } else {
        result::ok(())
    }
}

// ─── 公开 API：accept（返回新 fd）────────────────────────────
func accept(int sockfd) result[int, net_error] {
    let newfd = __sys_accept(sockfd)
    if newfd < 0 {
        result::err(make_net_error("accept"))
    } else {
        result::ok(newfd)
    }
}

// ─── 公开 API：accept + 获取对端地址 ─────────────────────────
func accept_addr(int sockfd) result[accept_result, net_error] {
    let newfd = __sys_accept(sockfd)
    if newfd < 0 {
        result::err(make_net_error("accept"))
    } else {
        result::ok(accept_result {
            fd: newfd,
            ip: __sys_peer_ip(newfd),
            port: __sys_peer_port(newfd),
        })
    }
}

struct accept_result {
    int    fd
    string ip
    int    port
}

func local_ip(int fd) string { __sys_local_ip(fd) }
func local_port(int fd) int { __sys_local_port(fd) }
func peer_ip(int fd) string { __sys_peer_ip(fd) }
func peer_port(int fd) int { __sys_peer_port(fd) }

// ─── 公开 API：connect ────────────────────────────────────────
func connect(int sockfd, string ip, int port, int family) result[(), net_error] {
    let r = __sys_connect(sockfd, ip, port, family)
    if r < 0 {
        result::err(make_net_error("connect"))
    } else {
        result::ok(())
    }
}

func connect_deadline(int sockfd, string host, int port, int family, int timeout_ms) result[(), net_error] {
    let r = __sys_connect_deadline(sockfd, host, port, family, timeout_ms)
    if r < 0 {
        result::err(make_net_error("connect"))
    } else {
        result::ok(())
    }
}

func resolve_ip(string host, int family) result[vec[string], net_error] {
    let addresses = __sys_resolve_ip(host, family)
    if len(addresses) == 0 && __sys_errno() != 0 {
        result::err(make_net_error("resolve"))
    } else {
        result::ok(addresses)
    }
}

// ─── 公开 API：read（返回读到的字节串）──────────────────────
func read_string(int fd, int max_bytes) result[string, net_error] {
    let data = __sys_read_string(fd, max_bytes)
    if data == "" {
        // 检查是 EOF 还是错误
        let code = __sys_errno()
        if code == 0 {
            result::ok("")   // EOF
        } else {
            result::err(net_error { message: "read: " + __sys_strerror(code), errno_code: code })
        }
    } else {
        result::ok(data)
    }
}

// ─── 公开 API：write（发送字节串）────────────────────────────
func write_string(int fd, string data) result[int, net_error] {
    let n = __sys_write_string(fd, data)
    if n < 0 {
        result::err(make_net_error("write"))
    } else {
        result::ok(n)
    }
}

// UDP datagram I/O keeps the destination/source boundary explicit.
func sendto_string(int fd, string data, string ip, int port, int family) result[int, net_error] {
    let n = __sys_sendto_string(fd, data, ip, port, family)
    if n < 0 {
        result::err(make_net_error("sendto"))
    } else {
        result::ok(n)
    }
}

struct recvfrom_result {
    string data
    string ip
    int port
}

func recvfrom_string(int fd, int max_bytes) result[recvfrom_result, net_error] {
    let data = __sys_recvfrom_string(fd, max_bytes)
    let code = __sys_errno()
    if data == "" && code != 0 {
        result::err(net_error { message: "recvfrom: " + __sys_strerror(code), errno_code: code })
    } else {
        result::ok(recvfrom_result {
            data: data,
            ip: __sys_last_recvfrom_ip(),
            port: __sys_last_recvfrom_port(),
        })
    }
}

func sendfile(int out_fd, int in_fd, int offset, int count) result[int, net_error] {
    let n = __sys_sendfile(out_fd, in_fd, offset, count)
    if n < 0 { result::err(make_net_error("sendfile")) } else { result::ok(n) }
}

func splice(int in_fd, int out_fd, int count) result[int, net_error] {
    let n = __sys_splice(in_fd, out_fd, count)
    if n < 0 { result::err(make_net_error("splice")) } else { result::ok(n) }
}

func interface_addresses() result[vec[string], net_error] {
    let addresses = __sys_interface_addresses()
    if len(addresses) == 0 && __sys_errno() != 0 {
        result::err(make_net_error("getifaddrs"))
    } else {
        result::ok(addresses)
    }
}

// ─── 公开 API：close ──────────────────────────────────────────
func close(int fd) result[(), net_error] {
    let r = __sys_close(fd)
    if r < 0 {
        result::err(make_net_error("close"))
    } else {
        result::ok(())
    }
}

// ─── 公开 API：设置非阻塞模式 ─────────────────────────────────
func set_nonblocking(int fd) result[(), net_error] {
    let flags = __sys_fcntl(fd, F_GETFL, 0)
    if flags < 0 {
        return result::err(make_net_error("fcntl F_GETFL"))
    }
    let r = __sys_fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    if r < 0 {
        result::err(make_net_error("fcntl F_SETFL"))
    } else {
        result::ok(())
    }
}

// ─── 公开 API：SO_REUSEADDR ───────────────────────────────────
func set_reuseaddr(int fd) result[(), net_error] {
    let r = __sys_setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, 1)
    if r < 0 {
        result::err(make_net_error("setsockopt SO_REUSEADDR"))
    } else {
        result::ok(())
    }
}

// ─── 公开 API：TCP_NODELAY ────────────────────────────────────
func set_tcp_nodelay(int fd) result[(), net_error] {
    let r = __sys_setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, 1)
    if r < 0 {
        result::err(make_net_error("setsockopt TCP_NODELAY"))
    } else {
        result::ok(())
    }
}

// Relative timeouts in milliseconds. Zero clears the timeout.
func set_deadline_ms(int fd, int read_timeout_ms, int write_timeout_ms) result[(), net_error] {
    let r = __sys_set_deadline_ms(fd, read_timeout_ms, write_timeout_ms)
    if r < 0 {
        result::err(make_net_error("set deadline"))
    } else {
        result::ok(())
    }
}

func shutdown(int fd, int how) result[(), net_error] {
    let r = __sys_shutdown(fd, how)
    if r < 0 {
        result::err(make_net_error("shutdown"))
    } else {
        result::ok(())
    }
}

// ─── 公开 API：poll（单 fd 版本）─────────────────────────────
func poll_ready(int fd, int events, int timeout_ms) result[int, net_error] {
    let r = __sys_poll_ready(fd, events, timeout_ms)
    if r < 0 {
        result::err(make_net_error("poll"))
    } else {
        result::ok(r)
    }
}

// ─── 公开 API：I/O 事件通知器（kqueue/epoll 封装）────────────
func poller_create() result[int, net_error] {
    let pfd = __sys_poller_create()
    if pfd < 0 {
        result::err(make_net_error("poller_create"))
    } else {
        result::ok(pfd)
    }
}

func poller_add(int poller_fd, int fd, int events) result[(), net_error] {
    let r = __sys_poller_add(poller_fd, fd, events)
    if r < 0 {
        result::err(make_net_error("poller_add"))
    } else {
        result::ok(())
    }
}

func poller_del(int poller_fd, int fd) result[(), net_error] {
    let r = __sys_poller_del(poller_fd, fd)
    if r < 0 {
        result::err(make_net_error("poller_del"))
    } else {
        result::ok(())
    }
}

func poller_wait(int poller_fd, int max, int timeout_ms) result[vec[int], net_error] {
    let ready = __sys_poller_wait(poller_fd, max, timeout_ms)
    if __sys_errno() != 0 {
        result::err(make_net_error("poller_wait"))
    } else {
        result::ok(ready)
    }
}

// 兼容旧接口
func syscall_unix_unit_name() string { "src/syscall/syscall_unix" }
func syscall_unix_unit_ready() int   { 1 }
