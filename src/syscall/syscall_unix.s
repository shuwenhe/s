package src.syscall
use std.result.result
use std.vec.vec

struct net_error {
    string message
    int    errno_code
}
const af_unspec = 0
const af_inet = 2
const af_inet6 = 10
const af_unix = 1
const sock_stream = 1
const sock_dgram = 2
const sock_nonblock = 2048
const sock_cloexec = 524288
const ipproto_tcp = 6
const ipproto_udp = 17
const sol_socket = 1
const so_reuseaddr = 2
const so_reuseport = 15
const so_keepalive = 9
const tcp_nodelay = 1
const f_getfl = 3
const f_setfl = 4
const o_nonblock = 2048
const poll_in = 1
const poll_out = 4
const poll_err = 8
const poll_hup = 16
const poll_nval = 32
const shut_rd = 0
const shut_wr = 1
const shut_rdwr = 2
extern "intrinsic" func __sys_socket(int domain, int typ, int proto) int
extern "intrinsic" func __sys_bind(int sockfd, string ip, int port, int family) int
extern "intrinsic" func __sys_listen(int sockfd, int backlog) int
extern "intrinsic" func __sys_accept(int sockfd) int
extern "intrinsic" func __sys_connect(int sockfd, string ip, int port, int family) int
extern "intrinsic" func __sys_connect_deadline(int sockfd, string host, int port, int family, int timeout_ms) int
extern "intrinsic" func __sys_resolve_ip(string host, int family) vec[string]
extern "intrinsic" func __sys_read(int fd, vec[int] buf, int n) int
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
extern "intrinsic" func __sys_poller_create() int
extern "intrinsic" func __sys_poller_add(int poller_fd, int fd, int events) int
extern "intrinsic" func __sys_poller_del(int poller_fd, int fd) int
extern "intrinsic" func __sys_poller_wait(int poller_fd, int max, int timeout_ms) vec[int]

func make_net_error(string msg) net_error {
    code := __sys_errno()
    net_error {
        message:    msg + ": " + __sys_strerror(code),
        errno_code: code,
    }
}

func socket(int domain, int typ, int proto) (int, net_error) {
    fd := __sys_socket(domain, typ, proto)
    if fd < 0 {
        make_net_error("socket")
    } else {
        fd
    }
}

func bind(int sockfd, string ip, int port, int family) ((), net_error) {
    r := __sys_bind(sockfd, ip, port, family)
    if r < 0 {
        make_net_error("bind")
    } else {
        ()
    }
}

func listen(int sockfd, int backlog) ((), net_error) {
    r := __sys_listen(sockfd, backlog)
    if r < 0 {
        make_net_error("listen")
    } else {
        ()
    }
}

func accept(int sockfd) (int, net_error) {
    newfd := __sys_accept(sockfd)
    if newfd < 0 {
        make_net_error("accept")
    } else {
        newfd
    }
}

func accept_addr(int sockfd) (accept_result, net_error) {
    newfd := __sys_accept(sockfd)
    if newfd < 0 {
        make_net_error("accept")
    } else {
        accept_result {
            fd: newfd,
            ip: __sys_peer_ip(newfd),
            port: __sys_peer_port(newfd),
        }
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

func connect(int sockfd, string ip, int port, int family) ((), net_error) {
    r := __sys_connect(sockfd, ip, port, family)
    if r < 0 {
        make_net_error("connect")
    } else {
        ()
    }
}

func connect_deadline(int sockfd, string host, int port, int family, int timeout_ms) ((), net_error) {
    r := __sys_connect_deadline(sockfd, host, port, family, timeout_ms)
    if r < 0 {
        make_net_error("connect")
    } else {
        ()
    }
}

func resolve_ip(string host, int family) (vec[string], net_error) {
    addresses := __sys_resolve_ip(host, family)
    if len(addresses) == 0 && __sys_errno() != 0 {
        make_net_error("resolve")
    } else {
        addresses
    }
}

func read_string(int fd, int max_bytes) (string, net_error) {
    data := __sys_read_string(fd, max_bytes)
    if data == "" {
        code := __sys_errno()
        if code == 0 {
            ""
        } else {
            net_error { message: "read: " + __sys_strerror(code), errno_code: code }
        }
    } else {
        data
    }
}

func write_string(int fd, string data) (int, net_error) {
    n := __sys_write_string(fd, data)
    if n < 0 {
        make_net_error("write")
    } else {
        n
    }
}

func sendto_string(int fd, string data, string ip, int port, int family) (int, net_error) {
    n := __sys_sendto_string(fd, data, ip, port, family)
    if n < 0 {
        make_net_error("sendto")
    } else {
        n
    }
}

struct recvfrom_result {
    string data
    string ip
    int port
}

func recvfrom_string(int fd, int max_bytes) (recvfrom_result, net_error) {
    data := __sys_recvfrom_string(fd, max_bytes)
    code := __sys_errno()
    if data == "" && code != 0 {
        net_error { message: "recvfrom: " + __sys_strerror(code), errno_code: code }
    } else {
        recvfrom_result {
            data: data,
            ip: __sys_last_recvfrom_ip(),
            port: __sys_last_recvfrom_port(),
        }
    }
}

func sendfile(int out_fd, int in_fd, int offset, int count) (int, net_error) {
    n := __sys_sendfile(out_fd, in_fd, offset, count)
    if n < 0 { make_net_error("sendfile") } else { n }
}

func splice(int in_fd, int out_fd, int count) (int, net_error) {
    n := __sys_splice(in_fd, out_fd, count)
    if n < 0 { make_net_error("splice") } else { n }
}

func interface_addresses() (vec[string], net_error) {
    addresses := __sys_interface_addresses()
    if len(addresses) == 0 && __sys_errno() != 0 {
        make_net_error("getifaddrs")
    } else {
        addresses
    }
}

func close(int fd) ((), net_error) {
    r := __sys_close(fd)
    if r < 0 {
        make_net_error("close")
    } else {
        ()
    }
}

func set_nonblocking(int fd) ((), net_error) {
    flags := __sys_fcntl(fd, f_getfl, 0)
    if flags < 0 {
        return make_net_error("fcntl F_GETFL")
    }
    r := __sys_fcntl(fd, f_setfl, flags | o_nonblock)
    if r < 0 {
        make_net_error("fcntl F_SETFL")
    } else {
        ()
    }
}

func set_reuseaddr(int fd) ((), net_error) {
    r := __sys_setsockopt(fd, sol_socket, so_reuseaddr, 1)
    if r < 0 {
        make_net_error("setsockopt SO_REUSEADDR")
    } else {
        ()
    }
}

func set_tcp_nodelay(int fd) ((), net_error) {
    r := __sys_setsockopt(fd, ipproto_tcp, tcp_nodelay, 1)
    if r < 0 {
        make_net_error("setsockopt TCP_NODELAY")
    } else {
        ()
    }
}

func set_deadline_ms(int fd, int read_timeout_ms, int write_timeout_ms) ((), net_error) {
    r := __sys_set_deadline_ms(fd, read_timeout_ms, write_timeout_ms)
    if r < 0 {
        make_net_error("set deadline")
    } else {
        ()
    }
}

func shutdown(int fd, int how) ((), net_error) {
    r := __sys_shutdown(fd, how)
    if r < 0 {
        make_net_error("shutdown")
    } else {
        ()
    }
}

func poll_ready(int fd, int events, int timeout_ms) (int, net_error) {
    r := __sys_poll_ready(fd, events, timeout_ms)
    if r < 0 {
        make_net_error("poll")
    } else {
        r
    }
}

func poller_create() (int, net_error) {
    pfd := __sys_poller_create()
    if pfd < 0 {
        make_net_error("poller_create")
    } else {
        pfd
    }
}

func poller_add(int poller_fd, int fd, int events) ((), net_error) {
    r := __sys_poller_add(poller_fd, fd, events)
    if r < 0 {
        make_net_error("poller_add")
    } else {
        ()
    }
}

func poller_del(int poller_fd, int fd) ((), net_error) {
    r := __sys_poller_del(poller_fd, fd)
    if r < 0 {
        make_net_error("poller_del")
    } else {
        ()
    }
}

func poller_wait(int poller_fd, int max, int timeout_ms) (vec[int], net_error) {
    ready := __sys_poller_wait(poller_fd, max, timeout_ms)
    if __sys_errno() != 0 {
        make_net_error("poller_wait")
    } else {
        ready
    }
}

func syscall_unix_unit_name() string { "src/syscall/syscall_unix" }

func syscall_unix_unit_ready() int   { 1 }
