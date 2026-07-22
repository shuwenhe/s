package src.net.internal

extern func socket(int family, int type, int protocol) int
extern func bind(int sockfd, *Sockaddr addr, int addrlen) int
extern func listen(int sockfd, int backlog) int
extern func accept(int sockfd, *Sockaddr addr, *int addrlen) int
extern func connect(int sockfd, *Sockaddr addr, int addrlen) int

extern func read(int fd, *byte buf, int len) int
extern func write(int fd, *byte buf, int len) int
extern func sendto(int sockfd, *byte buf, int len, int flags, *Sockaddr dest_addr, int addrlen) int
extern func recvfrom(int sockfd, *byte buf, int len, int flags, *Sockaddr src_addr, *int addrlen) int
extern func close(int fd) int

extern func setsockopt(int sockfd, int level, int optname, *byte optval, int optlen) int
extern func getsockopt(int sockfd, int level, int optname, *byte optval, *int optlen) int

extern func getpeername(int sockfd, *Sockaddr addr, *int addrlen) int
extern func getsockname(int sockfd, *Sockaddr addr, *int addrlen) int

extern func poll(*Pollfd fds, int nfds, int timeout) int
extern func select(int nfds, *byte readfds, *byte writefds, *byte exceptfds, *byte timeout) int

extern func shutdown(int sockfd, int how) int

extern func fcntl(int fd, int cmd, int arg) int
extern func errno_location() *int

const F_GETFL = 3
const F_SETFL = 4
const O_NONBLOCK = 2048

func get_errno() int {
    *errno_location()
}

func clear_errno() {
    *errno_location() = 0
}

func set_errno(err: int) {
    *errno_location() = err
}

func sys_socket(family: int, socktype: int, protocol: int) (int, int) {
    clear_errno()
    let fd = socket(family, socktype | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol)
    if fd < 0 {
        return fd, get_errno()
    }
    fd, 0
}

func sys_close(fd: int) int {
    clear_errno()
    close(fd)
    if close(fd) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_bind(fd: int, addr: *Sockaddr, addrlen: int) int {
    clear_errno()
    if bind(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_listen(fd: int, backlog: int) int {
    clear_errno()
    if listen(fd, backlog) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_accept(fd: int, addr: *Sockaddr, addrlen: *int) (int, int) {
    clear_errno()
    let client_fd = accept(fd, addr, addrlen)
    if client_fd < 0 {
        return client_fd, get_errno()
    }
    client_fd, 0
}

func sys_connect(fd: int, addr: *Sockaddr, addrlen: int) int {
    clear_errno()
    if connect(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_read(fd: int, buf: *byte, len: int) (int, int) {
    clear_errno()
    let n = read(fd, buf, len)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

func sys_write(fd: int, buf: *byte, len: int) (int, int) {
    clear_errno()
    let n = write(fd, buf, len)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

func sys_sendto(fd: int, buf: *byte, len: int, dest_addr: *Sockaddr, addrlen: int) (int, int) {
    clear_errno()
    let n = sendto(fd, buf, len, 0, dest_addr, addrlen)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

func sys_recvfrom(fd: int, buf: *byte, len: int, src_addr: *Sockaddr, addrlen: *int) (int, int) {
    clear_errno()
    let n = recvfrom(fd, buf, len, 0, src_addr, addrlen)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

func sys_setsockopt(fd: int, level: int, optname: int, optval: *byte, optlen: int) int {
    clear_errno()
    if setsockopt(fd, level, optname, optval, optlen) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_getsockopt(fd: int, level: int, optname: int, optval: *byte, optlen: *int) int {
    clear_errno()
    if getsockopt(fd, level, optname, optval, optlen) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_set_nonblocking(fd: int) int {
    clear_errno()
    let flags = fcntl(fd, F_GETFL, 0)
    if flags < 0 {
        return get_errno()
    }

    if fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_getsockname(fd: int, addr: *Sockaddr, addrlen: *int) int {
    clear_errno()
    if getsockname(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_getpeername(fd: int, addr: *Sockaddr, addrlen: *int) int {
    clear_errno()
    if getpeername(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

func sys_poll(fds: *Pollfd, nfds: int, timeout_ms: int) (int, int) {
    clear_errno()
    let n = poll(fds, nfds, timeout_ms)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

func sys_shutdown(fd: int, how: int) int {
    clear_errno()
    if shutdown(fd, how) < 0 {
        get_errno()
    } else {
        0
    }
}

func ipv4_to_sockaddr(ip_str: *byte, port: int) (SockaddrInet, bool) {
    var addr SockaddrInet
    addr.sin_family = AF_INET
    addr.sin_port = htons(port)
    addr, true
}

func htons(host: int) int {
    ((host & 0xFF00) >> 8) | ((host & 0x00FF) << 8)
}

func htonl(host: int) int {
    let b1 = (host >> 24) & 0xFF
    let b2 = (host >> 16) & 0xFF
    let b3 = (host >> 8) & 0xFF
    let b4 = host & 0xFF
    (b4 << 24) | (b3 << 16) | (b2 << 8) | b1
}
