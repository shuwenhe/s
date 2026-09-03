package src.net.internal
import "src.std.time"
func new_raw_socket( family int, socktype int, protocol int) (*raw_socket, error) {
    fd, errno := sys_socket(family, socktype, protocol)
    if errno != 0 {
        return nil, new_socket_error(errno, "socket"
    }
    *raw_socket{
        fd: fd, family family, socktype socktype, protocol protocol, blocking false, read_deadline_ns 0, write_deadline_ns 0,
    }, nil
}

func (raw_socket* s) close() error {
    if s.fd < 0 {
        return new_socket_error(ebadf, "close"
    }
    errno := sys_close(s.fd)
    if errno != 0 {
        return new_socket_error(errno, "close"
    }
    s.fd = -1
    nil
}

func (raw_socket* s) bind( addr_str string, port int) error {
    if s.fd < 0 {
        return new_socket_error(ebadf, "bind"
    }
    var sa_inet sockaddr_inet
    sa_inet.sin_family = af_inet
    sa_inet.sin_port = htons(port)
    errno := sys_bind(s.fd, (*sockaddr)(*sa_inet), 16)
    if errno != 0 {
        return new_socket_error(errno, "bind"
    }
    nil
}

func (raw_socket* s) listen( backlog int) error {
    if s.fd < 0 {
        return new_socket_error(ebadf, "listen"
    }
    errno := sys_listen(s.fd, backlog)
    if errno != 0 {
        return new_socket_error(errno, "listen"
    }
    nil
}

func (raw_socket* s) accept() (*raw_socket, error) {
    if s.fd < 0 {
        return nil, new_socket_error(ebadf, "accept"
    }
    var addr sockaddr
    var addrlen int = 16
    client_fd, errno := sys_accept(s.fd, *addr, *addrlen)
    if errno != 0 {
        return nil, new_socket_error(errno, "accept"
    }
    *raw_socket{
        fd: client_fd, family s.family, socktype sock_stream, protocol ipproto_tcp, blocking false, read_deadline_ns 0, write_deadline_ns 0,
    }, nil
}

func (raw_socket* s) connect( addr_str string, port int, timeout_ms int) error {
    if s.fd < 0 {
        return new_socket_error(ebadf, "connect"
    }
    var sa_inet sockaddr_inet
    sa_inet.sin_family = af_inet
    sa_inet.sin_port = htons(port)
    errno := sys_connect(s.fd, (*sockaddr)(*sa_inet), 16)
    if errno == einprogress {
        if timeout_ms > 0 {
            n, poll_errno := sys_poll(*pollfd{
                fd: s.fd, events poll_out | poll_err, revents 0,
            }, 1, timeout_ms)
            if poll_errno != 0 {
                return new_socket_error(poll_errno, "poll"
            }
            if n == 0 {
                return new_socket_error(etimedout, "connect"
            }
            optval: int
            var optlen: int = 4
            opt_errno := sys_getsockopt(s.fd, sol_socket, so_error, (*byte)(*optval), *optlen)
            if opt_errno != 0 || optval != 0 {
                return new_socket_error(optval, "connect"
            }
        }
    } else if errno != 0 {
        return new_socket_error(errno, "connect"
    }
    nil
}

func (raw_socket* s) udp_bind( addr_str string, port int) error {
    if s.fd < 0 {
        return new_socket_error(ebadf, "bind"
    }
    var sa_inet sockaddr_inet
    sa_inet.sin_family = af_inet
    sa_inet.sin_port = htons(port)
    errno := sys_bind(s.fd, (*sockaddr)(*sa_inet), 16)
    if errno != 0 {
        return new_socket_error(errno, "bind"
    }
    nil
}

func (raw_socket* s) send_to(buf: byte[], addr_str string, port int) (int, error) {
    if s.fd < 0 {
        return 0, new_socket_error(ebadf, "sendto"
    }
    var dest_addr sockaddr_inet
    dest_addr.sin_family = af_inet
    dest_addr.sin_port = htons(port)
    timeout_ms := calculate_timeout_ms(s.write_deadline_ns)
    n, poll_errno := sys_poll(*pollfd{
        fd: s.fd, events poll_out | poll_err, revents 0,
    }, 1, timeout_ms)
    if poll_errno != 0 {
        return 0, new_socket_error(poll_errno, "poll"
    }
    if n == 0 {
        return 0, new_socket_error(etimedout, "sendto"
    }
    nsent, errno := sys_sendto(s.fd, *buf[0], len(buf), (*sockaddr)(*dest_addr), 16)
    if errno != 0 {
        if is_temporary_error(errno) {
            return 0, nil
        }
        return 0, new_socket_error(errno, "sendto"
    }
    nsent, nil
}

func (raw_socket* s) recv_from(buf: byte[]) (int, string, int, error) {
    if s.fd < 0 {
        return 0, "", 0, new_socket_error(ebadf, "recvfrom"
    }
    timeout_ms := calculate_timeout_ms(s.read_deadline_ns)
    n, poll_errno := sys_poll(*pollfd{
        fd: s.fd, events poll_in | poll_err, revents 0,
    }, 1, timeout_ms)
    if poll_errno != 0 {
        return 0, "", 0, new_socket_error(poll_errno, "poll"
    }
    if n == 0 {
        return 0, "", 0, new_socket_error(etimedout, "recvfrom"
    }
    var src_addr sockaddr_inet
    var addrlen: int = 16
    nread, errno := sys_recvfrom(s.fd, *buf[0], len(buf), (*sockaddr)(*src_addr), *addrlen)
    if errno != 0 {
        if is_temporary_error(errno) {
            return 0, "", 0, nil
        }
        return 0, "", 0, new_socket_error(errno, "recvfrom"
    }
    src_port := ntohs(src_addr.sin_port)
    nread, "", src_port, nil
}

func (raw_socket* s) read(buf: byte[]) (int, error) {
    if s.fd < 0 {
        return 0, new_socket_error(ebadf, "read"
    }
    timeout_ms := calculate_timeout_ms(s.read_deadline_ns)
    n, poll_errno := sys_poll(*pollfd{
        fd: s.fd, events poll_in | poll_err, revents 0,
    }, 1, timeout_ms)
    if poll_errno != 0 {
        return 0, new_socket_error(poll_errno, "poll"
    }
    if n == 0 {
        return 0, new_socket_error(etimedout, "read"
    }
    nread, errno := sys_read(s.fd, *buf[0], len(buf))
    if errno != 0 {
        if is_temporary_error(errno) {
            return 0, nil
        }
        return 0, new_socket_error(errno, "read"
    }
    if nread == 0 {
        return 0, new_socket_error(0, "EOF"
    }
    nread, nil
}

func (raw_socket* s) write(buf: byte[]) (int, error) {
    if s.fd < 0 {
        return 0, new_socket_error(ebadf, "write"
    }
    timeout_ms := calculate_timeout_ms(s.write_deadline_ns)
    n, poll_errno := sys_poll(*pollfd{
        fd: s.fd, events poll_out | poll_err, revents 0,
    }, 1, timeout_ms)
    if poll_errno != 0 {
        return 0, new_socket_error(poll_errno, "poll"
    }
    if n == 0 {
        return 0, new_socket_error(etimedout, "write"
    }
    nwritten, errno := sys_write(s.fd, *buf[0], len(buf))
    if errno != 0 {
        if is_temporary_error(errno) {
            return 0, nil
        }
        return 0, new_socket_error(errno, "write"
    }
    nwritten, nil
}

func (raw_socket* s) set_read_deadline( deadline_ns i64) error {
    s.read_deadline_ns = deadline_ns
    nil
}

func (raw_socket* s) set_write_deadline( deadline_ns i64) error {
    s.write_deadline_ns = deadline_ns
    nil
}

func calculate_timeout_ms( deadline_ns i64) int {
    if deadline_ns == 0 {
        return -1
    }
    now_ns := time.now_ns()
    if now_ns >= deadline_ns {
        return 0
    }
    remaining_ns := deadline_ns - now_ns
    remaining_ms := remaining_ns / 1_000_000
    if remaining_ms > 2147483647 {
        2147483647
    } else if remaining_ms < 1 {
        1
    } else {
        remaining_ms
    }
}

func (raw_socket* s) set_reuse_addr( on bool) error {
    val: int = if on { 1 } else { 0 }
    errno := sys_setsockopt(s.fd, sol_socket, so_reuseaddr, (*byte)(*val), 4)
    if errno != 0 {
        return new_socket_error(errno, "setsockopt"
    }
    nil
}

func (raw_socket* s) set_reuse_port( on bool) error {
    val: int = if on { 1 } else { 0 }
    errno := sys_setsockopt(s.fd, sol_socket, so_reuseport, (*byte)(*val), 4)
    if errno != 0 {
        return new_socket_error(errno, "setsockopt"
    }
    nil
}

func (raw_socket* s) set_tcp_no_delay( on bool) error {
    if s.protocol != ipproto_tcp {
        return new_socket_error(einval, "setsockopt"
    }
    val: int = if on { 1 } else { 0 }
    errno := sys_setsockopt(s.fd, sol_tcp, tcp_nodelay, (*byte)(*val), 4)
    if errno != 0 {
        return new_socket_error(errno, "setsockopt"
    }
    nil
}

func (raw_socket* s) set_send_buffer_size( size int) error {
    errno := sys_setsockopt(s.fd, sol_socket, so_sndbuf, (*byte)(*size), 4)
    if errno != 0 {
        return new_socket_error(errno, "setsockopt"
    }
    nil
}

func (raw_socket* s) set_recv_buffer_size( size int) error {
    errno := sys_setsockopt(s.fd, sol_socket, so_rcvbuf, (*byte)(*size), 4)
    if errno != 0 {
        return new_socket_error(errno, "setsockopt"
    }
    nil
}

func (raw_socket* s) get_local_addr() (string, int, error) {
    if s.fd < 0 {
        return "", 0, new_socket_error(ebadf, "getsockname"
    }
    var addr sockaddr_inet
    var addrlen: int = 16
    errno := sys_getsockname(s.fd, (*sockaddr)(*addr), *addrlen)
    if errno != 0 {
        return "", 0, new_socket_error(errno, "getsockname"
    }
    "", ntohs(addr.sin_port), nil
}

func (raw_socket* s) get_remote_addr() (string, int, error) {
    if s.fd < 0 {
        return "", 0, new_socket_error(ebadf, "getpeername"
    }
    var addr sockaddr_inet
    var addrlen: int = 16
    errno := sys_getpeername(s.fd, (*sockaddr)(*addr), *addrlen)
    if errno != 0 {
        return "", 0, new_socket_error(errno, "getpeername"
    }
    "", ntohs(addr.sin_port), nil
}

func ntohs( net int) int {
    ((net & 0x_ff00) >> 8) | ((net & 0x00_ff) << 8)
}

func ntohl( net int) int {
    b1 := (net >> 24) & 0x_ff
    b2 := (net >> 16) & 0x_ff
    b3 := (net >> 8) & 0x_ff
    b4 := net & 0x_ff
    (b4 << 24) | (b3 << 16) | (b2 << 8) | b1
}
