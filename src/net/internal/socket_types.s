// Socket 类型定义和常量
package src.net.internal

// Socket 地址族常量
const AF_UNSPEC = 0
const AF_INET = 2
const AF_INET6 = 10
const AF_UNIX = 1
const AF_NETLINK = 16
const AF_PACKET = 17

// Socket 类型常量
const SOCK_STREAM = 1       // TCP
const SOCK_DGRAM = 2        // UDP
const SOCK_RAW = 3
const SOCK_SEQPACKET = 5
const SOCK_NONBLOCK = 2048
const SOCK_CLOEXEC = 524288

// 协议常量
const IPPROTO_IP = 0
const IPPROTO_TCP = 6
const IPPROTO_UDP = 17
const IPPROTO_ICMP = 1

// Socket 选项级别
const SOL_SOCKET = 1
const SOL_TCP = 6
const SOL_UDP = 17

// Socket 选项名称
const SO_REUSEADDR = 2
const SO_TYPE = 3
const SO_ERROR = 4
const SO_DONTROUTE = 5
const SO_BROADCAST = 6
const SO_SNDBUF = 7
const SO_RCVBUF = 8
const SO_KEEPALIVE = 9
const SO_OOBINLINE = 10
const SO_RCVTIMEO = 20
const SO_SNDTIMEO = 21
const SO_REUSEPORT = 15

// TCP 选项
const TCP_NODELAY = 1
const TCP_MAXSEG = 2
const TCP_CORK = 3
const TCP_KEEPIDLE = 4
const TCP_KEEPINTVL = 5
const TCP_KEEPCNT = 6

// Shutdown 常量
const SHUT_RD = 0
const SHUT_WR = 1
const SHUT_RDWR = 2

// Poll 事件标志
const POLLIN = 1
const POLLPRI = 2
const POLLOUT = 4
const POLLERR = 8
const POLLHUP = 16
const POLLNVAL = 32
const POLLRDNORM = 64
const POLLRDBAND = 128
const POLLWRNORM = 256
const POLLWRBAND = 512

// errno 值（与 libc 兼容）
const EPERM = 1
const ENOENT = 2
const ESRCH = 3
const EINTR = 4
const EIO = 5
const ENXIO = 6
const E2BIG = 7
const ENOEXEC = 8
const EBADF = 9
const ECHILD = 10
const EAGAIN = 11
const EWOULDBLOCK = 11        // 与 EAGAIN 相同
const ENOMEM = 12
const EACCES = 13
const EFAULT = 14
const ENOTBLK = 15
const EBUSY = 16
const EEXIST = 17
const EXDEV = 18
const ENODEV = 19
const ENOTDIR = 20
const EISDIR = 21
const EINVAL = 22
const ENFILE = 23
const EMFILE = 24
const ENOTTY = 25
const ETXTBSY = 26
const EFBIG = 27
const ENOSPC = 28
const ESPIPE = 29
const EROFS = 30
const EMLINK = 31
const EPIPE = 32
const EDOM = 33
const ERANGE = 34
const EDEADLK = 35
const ENAMETOOLONG = 36
const ENOLCK = 37
const ENOSYS = 38
const ENOTEMPTY = 39
const ELOOP = 40
const ECONNREFUSED = 111
const ECONNRESET = 104
const ECONNABORTED = 103
const ENETDOWN = 100
const ENETUNREACH = 101
const ENETRESET = 102
const ENOBUFS = 105
const ETIMEDOUT = 110
const EISCONN = 106
const ENOTCONN = 107
const EADDRNOTAVAIL = 99
const EADDRINUSE = 98
const EAFNOSUPPORT = 97
const EPROTOTYPE = 41
const ENOPROTOOPT = 92
const EPROTONOSUPPORT = 93
const ESOCKTNOSUPPORT = 94
const EOPNOTSUPP = 95

// IPv4 地址结构体 (sockaddr_in)
struct SockaddrInet {
    u16 sin_family      // AF_INET
    u16 sin_port        // 端口号（网络字节序）
    u32 sin_addr        // IPv4 地址
    []byte sin_zero     // 填充
}

// IPv6 地址结构体 (sockaddr_in6)
struct SockaddrInet6 {
    u16 sin6_family     // AF_INET6
    u16 sin6_port       // 端口号（网络字节序）
    u32 sin6_flowinfo   // 流信息
    []byte sin6_addr    // IPv6 地址（16 字节）
    u32 sin6_scope_id   // 作用域 ID
}

// 通用地址结构体 (sockaddr)
struct Sockaddr {
    u16 sa_family       // 地址族
    []byte sa_data      // 地址数据
}

// Poll 结构体
struct Pollfd {
    int fd              // 文件描述符
    i16 events          // 请求的事件
    i16 revents         // 返回的事件
}

// Socket 文件描述符包装
struct RawSocket {
    int fd              // 文件描述符
    int family          // AF_INET, AF_INET6, AF_UNIX
    int socktype        // SOCK_STREAM, SOCK_DGRAM
    int protocol        // IPPROTO_TCP, IPPROTO_UDP
    bool blocking       // 是否为阻塞模式
    i64 read_deadline_ns    // 读截止期限 (纳秒，0 表示无限期)
    i64 write_deadline_ns   // 写截止期限 (纳秒，0 表示无限期)
}

// TCP 连接相关结构
struct TCPConnState {
    RawSocket sock
    []byte local_addr   // 本地地址字符串
    []byte remote_addr  // 远程地址字符串
}

// UDP 连接相关结构
struct UDPConnState {
    RawSocket sock
    []byte local_addr
    []byte remote_addr
}

// TCP 监听相关结构
struct TCPListenerState {
    RawSocket sock
    []byte addr         // 监听地址
}

// Socket 操作错误类型
struct SocketError {
    int errno           // 系统错误号
    string message      // 错误消息
    string syscall_name // 失败的系统调用名称
}

func (e *SocketError) Error() string {
    e.syscall_name + ": " + e.message
}

// 创建 SocketError
func NewSocketError(errno: int, syscall_name: string) *SocketError {
    var msg string
    case errno {
    ECONNREFUSED → msg = "connection refused"
    ECONNRESET → msg = "connection reset by peer"
    ETIMEDOUT → msg = "operation timed out"
    EWOULDBLOCK → msg = "resource temporarily unavailable"
    ECONNABORTED → msg = "software caused connection abort"
    ENOTCONN → msg = "transport endpoint is not connected"
    EISCONN → msg = "transport endpoint is already connected"
    EADDRINUSE → msg = "address already in use"
    EADDRNOTAVAIL → msg = "cannot assign requested address"
    ENETDOWN → msg = "network is down"
    ENETUNREACH → msg = "network is unreachable"
    ENOBUFS → msg = "no buffer space available"
    EBADF → msg = "bad file descriptor"
    EINVAL → msg = "invalid argument"
    EMFILE → msg = "too many open files"
    ENFILE → msg = "file table overflow"
    EACCES → msg = "permission denied"
    EPERM → msg = "operation not permitted"
    default → msg = "errno: " + itoa(errno)
    }
    
    &SocketError{
        errno: errno,
        message: msg,
        syscall_name: syscall_name,
    }
}

// 检查是否是临时错误（可重试）
func IsTemporaryError(errno: int) bool {
    errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR
}

// 检查是否是超时错误
func IsTimeoutError(errno: int) bool {
    errno == ETIMEDOUT
}
