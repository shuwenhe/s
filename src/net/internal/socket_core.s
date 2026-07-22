package src.net.internal

import "src.std.time"

func NewRawSocket(family: int, socktype: int, protocol: int) (*RawSocket, error) {
    let fd, errno = sys_socket(family, socktype, protocol)
    if errno != 0 {
        return nil, NewSocketError(errno, "socket")
    }

    &RawSocket{
        fd: fd,
        family: family,
        socktype: socktype,
        protocol: protocol,
        blocking: false,
        read_deadline_ns: 0,
        write_deadline_ns: 0,
    }, nil
}

func (s *RawSocket) Close() error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "close")
    }

    let errno = sys_close(s.fd)
    if errno != 0 {
        return NewSocketError(errno, "close")
    }

    s.fd = -1
    nil
}

func (s *RawSocket) Bind(addr_str: string, port: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "bind")
    }

    var sa_inet SockaddrInet
    sa_inet.sin_family = AF_INET
    sa_inet.sin_port = htons(port)

    let errno = sys_bind(s.fd, (*Sockaddr)(&sa_inet), 16)
    if errno != 0 {
        return NewSocketError(errno, "bind")
    }

    nil
}

func (s *RawSocket) Listen(backlog: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "listen")
    }

    let errno = sys_listen(s.fd, backlog)
    if errno != 0 {
        return NewSocketError(errno, "listen")
    }

    nil
}

func (s *RawSocket) Accept() (*RawSocket, error) {
    if s.fd < 0 {
        return nil, NewSocketError(EBADF, "accept")
    }

    var addr Sockaddr
    var addrlen int = 16

    let client_fd, errno = sys_accept(s.fd, &addr, &addrlen)
    if errno != 0 {
        return nil, NewSocketError(errno, "accept")
    }

    &RawSocket{
        fd: client_fd,
        family: s.family,
        socktype: SOCK_STREAM,
        protocol: IPPROTO_TCP,
        blocking: false,
        read_deadline_ns: 0,
        write_deadline_ns: 0,
    }, nil
}

func (s *RawSocket) Connect(addr_str: string, port: int, timeout_ms: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "connect")
    }

    var sa_inet SockaddrInet
    sa_inet.sin_family = AF_INET
    sa_inet.sin_port = htons(port)

    let errno = sys_connect(s.fd, (*Sockaddr)(&sa_inet), 16)

    if errno == EINPROGRESS {
        if timeout_ms > 0 {
            let n, poll_errno = sys_poll(&Pollfd{
                fd: s.fd,
                events: POLLOUT | POLLERR,
                revents: 0,
            }, 1, timeout_ms)

            if poll_errno != 0 {
                return NewSocketError(poll_errno, "poll")
            }

            if n == 0 {
                return NewSocketError(ETIMEDOUT, "connect")
            }

            let optval: int
            var optlen: int = 4
            let opt_errno = sys_getsockopt(s.fd, SOL_SOCKET, SO_ERROR, (*byte)(&optval), &optlen)
            if opt_errno != 0 || optval != 0 {
                return NewSocketError(optval, "connect")
            }
        }
    } else if errno != 0 {
        return NewSocketError(errno, "connect")
    }

    nil
}

func (s *RawSocket) UDPBind(addr_str: string, port: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "bind")
    }

    var sa_inet SockaddrInet
    sa_inet.sin_family = AF_INET
    sa_inet.sin_port = htons(port)

    let errno = sys_bind(s.fd, (*Sockaddr)(&sa_inet), 16)
    if errno != 0 {
        return NewSocketError(errno, "bind")
    }

    nil
}

func (s *RawSocket) SendTo(buf: []byte, addr_str: string, port: int) (int, error) {
    if s.fd < 0 {
        return 0, NewSocketError(EBADF, "sendto")
    }

    var dest_addr SockaddrInet
    dest_addr.sin_family = AF_INET
    dest_addr.sin_port = htons(port)

    let timeout_ms = calculate_timeout_ms(s.write_deadline_ns)

    let n, poll_errno = sys_poll(&Pollfd{
        fd: s.fd,
        events: POLLOUT | POLLERR,
        revents: 0,
    }, 1, timeout_ms)

    if poll_errno != 0 {
        return 0, NewSocketError(poll_errno, "poll")
    }

    if n == 0 {
        return 0, NewSocketError(ETIMEDOUT, "sendto")
    }

    let nsent, errno = sys_sendto(s.fd, &buf[0], len(buf), (*Sockaddr)(&dest_addr), 16)
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, nil
        }
        return 0, NewSocketError(errno, "sendto")
    }

    nsent, nil
}

func (s *RawSocket) RecvFrom(buf: []byte) (int, string, int, error) {
    if s.fd < 0 {
        return 0, "", 0, NewSocketError(EBADF, "recvfrom")
    }

    let timeout_ms = calculate_timeout_ms(s.read_deadline_ns)

    let n, poll_errno = sys_poll(&Pollfd{
        fd: s.fd,
        events: POLLIN | POLLERR,
        revents: 0,
    }, 1, timeout_ms)

    if poll_errno != 0 {
        return 0, "", 0, NewSocketError(poll_errno, "poll")
    }

    if n == 0 {
        return 0, "", 0, NewSocketError(ETIMEDOUT, "recvfrom")
    }

    var src_addr SockaddrInet
    var addrlen: int = 16

    let nread, errno = sys_recvfrom(s.fd, &buf[0], len(buf), (*Sockaddr)(&src_addr), &addrlen)
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, "", 0, nil
        }
        return 0, "", 0, NewSocketError(errno, "recvfrom")
    }

    let src_port = ntohs(src_addr.sin_port)

    nread, "", src_port, nil
}

func (s *RawSocket) Read(buf: []byte) (int, error) {
    if s.fd < 0 {
        return 0, NewSocketError(EBADF, "read")
    }

    let timeout_ms = calculate_timeout_ms(s.read_deadline_ns)

    let n, poll_errno = sys_poll(&Pollfd{
        fd: s.fd,
        events: POLLIN | POLLERR,
        revents: 0,
    }, 1, timeout_ms)

    if poll_errno != 0 {
        return 0, NewSocketError(poll_errno, "poll")
    }

    if n == 0 {
        return 0, NewSocketError(ETIMEDOUT, "read")
    }

    let nread, errno = sys_read(s.fd, &buf[0], len(buf))
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, nil
        }
        return 0, NewSocketError(errno, "read")
    }

    if nread == 0 {
        return 0, NewSocketError(0, "EOF")
    }

    nread, nil
}

func (s *RawSocket) Write(buf: []byte) (int, error) {
    if s.fd < 0 {
        return 0, NewSocketError(EBADF, "write")
    }

    let timeout_ms = calculate_timeout_ms(s.write_deadline_ns)

    let n, poll_errno = sys_poll(&Pollfd{
        fd: s.fd,
        events: POLLOUT | POLLERR,
        revents: 0,
    }, 1, timeout_ms)

    if poll_errno != 0 {
        return 0, NewSocketError(poll_errno, "poll")
    }

    if n == 0 {
        return 0, NewSocketError(ETIMEDOUT, "write")
    }

    let nwritten, errno = sys_write(s.fd, &buf[0], len(buf))
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, nil
        }
        return 0, NewSocketError(errno, "write")
    }

    nwritten, nil
}

func (s *RawSocket) SetReadDeadline(deadline_ns: i64) error {
    s.read_deadline_ns = deadline_ns
    nil
}

func (s *RawSocket) SetWriteDeadline(deadline_ns: i64) error {
    s.write_deadline_ns = deadline_ns
    nil
}

func calculate_timeout_ms(deadline_ns: i64) int {
    if deadline_ns == 0 {
        return -1
    }

    let now_ns = time.now_ns()

    if now_ns >= deadline_ns {
        return 0
    }

    let remaining_ns = deadline_ns - now_ns
    let remaining_ms = remaining_ns / 1_000_000

    if remaining_ms > 2147483647 {
        2147483647
    } else if remaining_ms < 1 {
        1
    } else {
        remaining_ms
    }
}

func (s *RawSocket) SetReuseAddr(on: bool) error {
    let val: int = if on { 1 } else { 0 }
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_REUSEADDR, (*byte)(&val), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

func (s *RawSocket) SetReusePort(on: bool) error {
    let val: int = if on { 1 } else { 0 }
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_REUSEPORT, (*byte)(&val), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

func (s *RawSocket) SetTCPNoDelay(on: bool) error {
    if s.protocol != IPPROTO_TCP {
        return NewSocketError(EINVAL, "setsockopt")
    }

    let val: int = if on { 1 } else { 0 }
    let errno = sys_setsockopt(s.fd, SOL_TCP, TCP_NODELAY, (*byte)(&val), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

func (s *RawSocket) SetSendBufferSize(size: int) error {
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_SNDBUF, (*byte)(&size), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

func (s *RawSocket) SetRecvBufferSize(size: int) error {
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_RCVBUF, (*byte)(&size), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

func (s *RawSocket) GetLocalAddr() (string, int, error) {
    if s.fd < 0 {
        return "", 0, NewSocketError(EBADF, "getsockname")
    }

    var addr SockaddrInet
    var addrlen: int = 16

    let errno = sys_getsockname(s.fd, (*Sockaddr)(&addr), &addrlen)
    if errno != 0 {
        return "", 0, NewSocketError(errno, "getsockname")
    }

    "", ntohs(addr.sin_port), nil
}

func (s *RawSocket) GetRemoteAddr() (string, int, error) {
    if s.fd < 0 {
        return "", 0, NewSocketError(EBADF, "getpeername")
    }

    var addr SockaddrInet
    var addrlen: int = 16

    let errno = sys_getpeername(s.fd, (*Sockaddr)(&addr), &addrlen)
    if errno != 0 {
        return "", 0, NewSocketError(errno, "getpeername")
    }

    "", ntohs(addr.sin_port), nil
}

func ntohs(net: int) int {
    ((net & 0xFF00) >> 8) | ((net & 0x00FF) << 8)
}

func ntohl(net: int) int {
    let b1 = (net >> 24) & 0xFF
    let b2 = (net >> 16) & 0xFF
    let b3 = (net >> 8) & 0xFF
    let b4 = net & 0xFF
    (b4 << 24) | (b3 << 16) | (b2 << 8) | b1
}
