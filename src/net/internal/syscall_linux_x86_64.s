// Linux x86_64 Socket 系统调用绑定
// 通过 libc 包装调用 Linux 系统调用
package src.net.internal

// ============================================================================
// 外部 libc 函数声明
// ============================================================================

// Socket 创建和操作
extern func socket(int family, int type, int protocol) int
extern func bind(int sockfd, *Sockaddr addr, int addrlen) int
extern func listen(int sockfd, int backlog) int
extern func accept(int sockfd, *Sockaddr addr, *int addrlen) int
extern func connect(int sockfd, *Sockaddr addr, int addrlen) int

// I/O 操作
extern func read(int fd, *byte buf, int len) int
extern func write(int fd, *byte buf, int len) int
extern func sendto(int sockfd, *byte buf, int len, int flags, *Sockaddr dest_addr, int addrlen) int
extern func recvfrom(int sockfd, *byte buf, int len, int flags, *Sockaddr src_addr, *int addrlen) int
extern func close(int fd) int

// Socket 选项
extern func setsockopt(int sockfd, int level, int optname, *byte optval, int optlen) int
extern func getsockopt(int sockfd, int level, int optname, *byte optval, *int optlen) int

// 地址信息
extern func getpeername(int sockfd, *Sockaddr addr, *int addrlen) int
extern func getsockname(int sockfd, *Sockaddr addr, *int addrlen) int

// 多路复用
extern func poll(*Pollfd fds, int nfds, int timeout) int
extern func select(int nfds, *byte readfds, *byte writefds, *byte exceptfds, *byte timeout) int

// 关闭连接
extern func shutdown(int sockfd, int how) int

// 其他
extern func fcntl(int fd, int cmd, int arg) int
extern func errno_location() *int

// ============================================================================
// 平台相关常量
// ============================================================================

// fcntl 常量
const F_GETFL = 3
const F_SETFL = 4
const O_NONBLOCK = 2048

// ============================================================================
// 内部辅助函数
// ============================================================================

// 获取当前 errno 值
func get_errno() int {
    *errno_location()
}

// 清除 errno
func clear_errno() {
    *errno_location() = 0
}

// 设置 errno
func set_errno(err: int) {
    *errno_location() = err
}

// ============================================================================
// Socket 创建和销毁
// ============================================================================

// 创建 socket 文件描述符
// 返回 (fd, errno)
func sys_socket(family: int, socktype: int, protocol: int) (int, int) {
    clear_errno()
    let fd = socket(family, socktype | SOCK_NONBLOCK | SOCK_CLOEXEC, protocol)
    if fd < 0 {
        return fd, get_errno()
    }
    fd, 0
}

// 关闭 socket 文件描述符
func sys_close(fd: int) int {
    clear_errno()
    close(fd)
    if close(fd) < 0 {
        get_errno()
    } else {
        0
    }
}

// ============================================================================
// 连接操作
// ============================================================================

// 绑定 socket 到地址
func sys_bind(fd: int, addr: *Sockaddr, addrlen: int) int {
    clear_errno()
    if bind(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

// 标记 socket 为监听状态
func sys_listen(fd: int, backlog: int) int {
    clear_errno()
    if listen(fd, backlog) < 0 {
        get_errno()
    } else {
        0
    }
}

// 接受客户端连接
func sys_accept(fd: int, addr: *Sockaddr, addrlen: *int) (int, int) {
    clear_errno()
    let client_fd = accept(fd, addr, addrlen)
    if client_fd < 0 {
        return client_fd, get_errno()
    }
    client_fd, 0
}

// 连接到远程地址
func sys_connect(fd: int, addr: *Sockaddr, addrlen: int) int {
    clear_errno()
    if connect(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

// ============================================================================
// 读写操作
// ============================================================================

// 从 socket 读取数据
func sys_read(fd: int, buf: *byte, len: int) (int, int) {
    clear_errno()
    let n = read(fd, buf, len)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

// 向 socket 写入数据
func sys_write(fd: int, buf: *byte, len: int) (int, int) {
    clear_errno()
    let n = write(fd, buf, len)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

// 发送数据到指定地址（UDP）
func sys_sendto(fd: int, buf: *byte, len: int, dest_addr: *Sockaddr, addrlen: int) (int, int) {
    clear_errno()
    let n = sendto(fd, buf, len, 0, dest_addr, addrlen)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

// 从 socket 接收数据并获取源地址（UDP）
func sys_recvfrom(fd: int, buf: *byte, len: int, src_addr: *Sockaddr, addrlen: *int) (int, int) {
    clear_errno()
    let n = recvfrom(fd, buf, len, 0, src_addr, addrlen)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

// ============================================================================
// Socket 选项
// ============================================================================

// 设置 socket 选项
func sys_setsockopt(fd: int, level: int, optname: int, optval: *byte, optlen: int) int {
    clear_errno()
    if setsockopt(fd, level, optname, optval, optlen) < 0 {
        get_errno()
    } else {
        0
    }
}

// 获取 socket 选项
func sys_getsockopt(fd: int, level: int, optname: int, optval: *byte, optlen: *int) int {
    clear_errno()
    if getsockopt(fd, level, optname, optval, optlen) < 0 {
        get_errno()
    } else {
        0
    }
}

// 设置 socket 为非阻塞模式
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

// ============================================================================
// 地址信息
// ============================================================================

// 获取 socket 本地地址
func sys_getsockname(fd: int, addr: *Sockaddr, addrlen: *int) int {
    clear_errno()
    if getsockname(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

// 获取 socket 远程地址
func sys_getpeername(fd: int, addr: *Sockaddr, addrlen: *int) int {
    clear_errno()
    if getpeername(fd, addr, addrlen) < 0 {
        get_errno()
    } else {
        0
    }
}

// ============================================================================
// 多路复用 I/O
// ============================================================================

// Poll 操作 - 等待文件描述符上的事件
// 返回 (就绪 fd 数, errno)
func sys_poll(fds: *Pollfd, nfds: int, timeout_ms: int) (int, int) {
    clear_errno()
    let n = poll(fds, nfds, timeout_ms)
    if n < 0 {
        return n, get_errno()
    }
    n, 0
}

// ============================================================================
// 连接关闭
// ============================================================================

// Shutdown socket（分方向关闭读写）
func sys_shutdown(fd: int, how: int) int {
    clear_errno()
    if shutdown(fd, how) < 0 {
        get_errno()
    } else {
        0
    }
}

// ============================================================================
// 高级功能 - 地址转换
// ============================================================================

// IPv4 字符串转 sockaddr_in 结构
func ipv4_to_sockaddr(ip_str: *byte, port: int) (SockaddrInet, bool) {
    // 简化实现：假设 IP 已经是正确格式
    // 实际应该调用 inet_aton() 或类似函数
    // 这里仅作示例
    var addr SockaddrInet
    addr.sin_family = AF_INET
    addr.sin_port = htons(port)  // 转换为网络字节序
    // addr.sin_addr = inet_aton(ip_str)  // TODO: 实现
    addr, true
}

// 网络字节序转换 (大端)
func htons(host: int) int {
    // 转换为网络字节序（大端）
    // x86_64 是小端，所以需要转换
    ((host & 0xFF00) >> 8) | ((host & 0x00FF) << 8)
}

func htonl(host: int) int {
    // 32 位转换
    let b1 = (host >> 24) & 0xFF
    let b2 = (host >> 16) & 0xFF
    let b3 = (host >> 8) & 0xFF
    let b4 = host & 0xFF
    (b4 << 24) | (b3 << 16) | (b2 << 8) | b1
}
