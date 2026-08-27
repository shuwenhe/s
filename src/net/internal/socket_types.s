package src.net.internal
const af_unspec = 0
const af_inet = 2
const af_inet6 = 10
const af_unix = 1
const af_netlink = 16
const af_packet = 17
const sock_stream = 1
const sock_dgram = 2
const sock_raw = 3
const sock_seqpacket = 5
const sock_nonblock = 2048
const sock_cloexec = 524288
const ipproto_ip = 0
const ipproto_tcp = 6
const ipproto_udp = 17
const ipproto_icmp = 1
const sol_socket = 1
const sol_tcp = 6
const sol_udp = 17
const so_reuseaddr = 2
const so_type = 3
const so_error = 4
const so_dontroute = 5
const so_broadcast = 6
const so_sndbuf = 7
const so_rcvbuf = 8
const so_keepalive = 9
const so_oobinline = 10
const so_rcvtimeo = 20
const so_sndtimeo = 21
const so_reuseport = 15
const tcp_nodelay = 1
const tcp_maxseg = 2
const tcp_cork = 3
const tcp_keepidle = 4
const tcp_keepintvl = 5
const tcp_keepcnt = 6
const shut_rd = 0
const shut_wr = 1
const shut_rdwr = 2
const poll_in = 1
const poll_pri = 2
const poll_out = 4
const poll_err = 8
const poll_hup = 16
const poll_nval = 32
const poll_rdnorm = 64
const poll_rdband = 128
const poll_wrnorm = 256
const poll_wrband = 512
const eperm = 1
const enoent = 2
const esrch = 3
const eintr = 4
const eio = 5
const enxio = 6
const e2big = 7
const enoexec = 8
const ebadf = 9
const echild = 10
const eagain = 11
const ewouldblock = 11
const enomem = 12
const eacces = 13
const efault = 14
const enotblk = 15
const ebusy = 16
const eexist = 17
const exdev = 18
const enodev = 19
const enotdir = 20
const eisdir = 21
const einval = 22
const enfile = 23
const emfile = 24
const enotty = 25
const etxtbsy = 26
const efbig = 27
const enospc = 28
const espipe = 29
const erofs = 30
const emlink = 31
const epipe = 32
const edom = 33
const erange = 34
const edeadlk = 35
const enametoolong = 36
const enolck = 37
const enosys = 38
const enotempty = 39
const eloop = 40
const econnrefused = 111
const econnreset = 104
const econnaborted = 103
const enetdown = 100
const enetunreach = 101
const enetreset = 102
const enobufs = 105
const etimedout = 110
const eisconn = 106
const enotconn = 107
const eaddrnotavail = 99
const eaddrinuse = 98
const eafnosupport = 97
const einprogress = 115
const eprototype = 41
const enoprotoopt = 92
const eprotonosupport = 93
const esocktnosupport = 94
const eopnotsupp = 95

struct sockaddr_inet {
    u16 sin_family
    u16 sin_port
    u32 sin_addr
    []byte sin_zero
}

struct sockaddr_inet6 {
    u16 sin6_family
    u16 sin6_port
    u32 sin6_flowinfo
    []byte sin6_addr
    u32 sin6_scope_id
}

struct sockaddr {
    u16 sa_family
    []byte sa_data
}

struct pollfd {
    int fd
    i16 events
    i16 revents
}

struct raw_socket {
    int fd
    int family
    int socktype
    int protocol
    bool blocking
    i64 read_deadline_ns
    i64 write_deadline_ns
}

struct tcp_conn_state {
    raw_socket sock
    []byte local_addr
    []byte remote_addr
}

struct udp_conn_state {
    raw_socket sock
    []byte local_addr
    []byte remote_addr
}

struct tcp_listener_state {
    raw_socket sock
    []byte addr
}

struct socket_error {
    int errno
    string message
    string syscall_name
}

func (socket_error* e) Error() string {
    e.syscall_name + ": " + e.message
}

func new_socket_error(errno: int, syscall_name: string) *socket_error {
    var msg string
    case errno {
    econnrefused → msg = "connection refused"
    econnreset → msg = "connection reset by peer"
    etimedout → msg = "operation timed out"
    ewouldblock → msg = "resource temporarily unavailable"
    econnaborted → msg = "software caused connection abort"
    enotconn → msg = "transport endpoint is not connected"
    eisconn → msg = "transport endpoint is already connected"
    eaddrinuse → msg = "address already in use"
    eaddrnotavail → msg = "cannot assign requested address"
    enetdown → msg = "network is down"
    enetunreach → msg = "network is unreachable"
    enobufs → msg = "no buffer space available"
    ebadf → msg = "bad file descriptor"
    einval → msg = "invalid argument"
    emfile → msg = "too many open files"
    enfile → msg = "file table overflow"
    eacces → msg = "permission denied"
    eperm → msg = "operation not permitted"
    default → msg = "errno: " + itoa(errno)
    }
    *socket_error{
        errno: errno,
        message: msg,
        syscall_name: syscall_name,
    }
}

func is_temporary_error(errno: int) bool {
    errno == eagain || errno == ewouldblock || errno == eintr
}

func is_timeout_error(errno: int) bool {
    errno == etimedout
}
