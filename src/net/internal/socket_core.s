// Socket 核心操作实现
// 提供跨平台的 Socket 操作接口
package src.net.internal

import "src.std.time"

// ============================================================================
// Socket 创建和销毁
// ============================================================================

// 创建新的 raw socket
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
        blocking: false,     // 默认非阻塞（使用 poll/epoll）
        read_deadline_ns: 0,
        write_deadline_ns: 0,
    }, nil
}

// 关闭 socket
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

// ============================================================================
// TCP 操作
// ============================================================================

// 绑定 TCP socket 到地址和端口
func (s *RawSocket) Bind(addr_str: string, port: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "bind")
    }
    
    // 解析地址字符串（简化实现）
    // 假设格式为 "127.0.0.1"
    var sa_inet SockaddrInet
    sa_inet.sin_family = AF_INET
    sa_inet.sin_port = htons(port)
    // sa_inet.sin_addr = parse_ipv4(addr_str)  // TODO: 实现 IP 地址解析
    
    // 调用 bind
    let errno = sys_bind(s.fd, (*Sockaddr)(&sa_inet), 16)  // sockaddr_in 长度为 16
    if errno != 0 {
        return NewSocketError(errno, "bind")
    }
    
    nil
}

// 开始监听连接（成为 TCP 服务器）
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

// 接受客户端连接
func (s *RawSocket) Accept() (*RawSocket, error) {
    if s.fd < 0 {
        return nil, NewSocketError(EBADF, "accept")
    }
    
    var addr Sockaddr
    var addrlen int = 16  // sockaddr_in 长度
    
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

// 连接到远程 TCP 地址
func (s *RawSocket) Connect(addr_str: string, port: int, timeout_ms: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "connect")
    }
    
    // 构建目标地址
    var sa_inet SockaddrInet
    sa_inet.sin_family = AF_INET
    sa_inet.sin_port = htons(port)
    // sa_inet.sin_addr = parse_ipv4(addr_str)  // TODO: 实现 IP 地址解析
    
    // 尝试连接
    let errno = sys_connect(s.fd, (*Sockaddr)(&sa_inet), 16)
    
    if errno == EINPROGRESS {
        // 非阻塞 socket 上连接进行中，使用 poll 等待
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
            
            // 检查连接是否成功
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

// ============================================================================
// UDP 操作
// ============================================================================

// UDP bind 到本地地址
func (s *RawSocket) UDPBind(addr_str: string, port: int) error {
    if s.fd < 0 {
        return NewSocketError(EBADF, "bind")
    }
    
    // 与 TCP bind 相同
    var sa_inet SockaddrInet
    sa_inet.sin_family = AF_INET
    sa_inet.sin_port = htons(port)
    
    let errno = sys_bind(s.fd, (*Sockaddr)(&sa_inet), 16)
    if errno != 0 {
        return NewSocketError(errno, "bind")
    }
    
    nil
}

// 发送 UDP 数据到指定地址
func (s *RawSocket) SendTo(buf: []byte, addr_str: string, port: int) (int, error) {
    if s.fd < 0 {
        return 0, NewSocketError(EBADF, "sendto")
    }
    
    // 构建目标地址
    var dest_addr SockaddrInet
    dest_addr.sin_family = AF_INET
    dest_addr.sin_port = htons(port)
    // dest_addr.sin_addr = parse_ipv4(addr_str)  // TODO: 实现 IP 地址解析
    
    // 计算 poll 超时
    let timeout_ms = calculate_timeout_ms(s.write_deadline_ns)
    
    // 等待 socket 可写
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
    
    // 发送数据
    let nsent, errno = sys_sendto(s.fd, &buf[0], len(buf), (*Sockaddr)(&dest_addr), 16)
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, nil  // 临时错误，重试
        }
        return 0, NewSocketError(errno, "sendto")
    }
    
    nsent, nil
}

// 接收 UDP 数据并获取源地址
func (s *RawSocket) RecvFrom(buf: []byte) (int, string, int, error) {
    if s.fd < 0 {
        return 0, "", 0, NewSocketError(EBADF, "recvfrom")
    }
    
    // 计算 poll 超时
    let timeout_ms = calculate_timeout_ms(s.read_deadline_ns)
    
    // 等待数据可读
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
    
    // 接收数据
    var src_addr SockaddrInet
    var addrlen: int = 16
    
    let nread, errno = sys_recvfrom(s.fd, &buf[0], len(buf), (*Sockaddr)(&src_addr), &addrlen)
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, "", 0, nil  // 临时错误，重试
        }
        return 0, "", 0, NewSocketError(errno, "recvfrom")
    }
    
    // 获取源地址和端口
    let src_port = ntohs(src_addr.sin_port)
    // 源 IP 地址解析需要 inet_ntoa 或类似函数
    // TODO: 实现 IPv4 地址转字符串
    
    nread, "", src_port, nil
}

// ============================================================================
// I/O 操作
// ============================================================================

// 从 socket 读取数据
// 如果设置了截止期限，等待该期限或数据到达，以先发生者为准
func (s *RawSocket) Read(buf: []byte) (int, error) {
    if s.fd < 0 {
        return 0, NewSocketError(EBADF, "read")
    }
    
    // 计算 poll 超时
    let timeout_ms = calculate_timeout_ms(s.read_deadline_ns)
    
    // 等待数据可读
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
    
    // 数据已就绪，进行读操作
    let nread, errno = sys_read(s.fd, &buf[0], len(buf))
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, nil  // 临时错误，重试
        }
        return 0, NewSocketError(errno, "read")
    }
    
    if nread == 0 {
        // 对端关闭连接
        return 0, NewSocketError(0, "EOF")
    }
    
    nread, nil
}

// 向 socket 写入数据
func (s *RawSocket) Write(buf: []byte) (int, error) {
    if s.fd < 0 {
        return 0, NewSocketError(EBADF, "write")
    }
    
    // 计算 poll 超时
    let timeout_ms = calculate_timeout_ms(s.write_deadline_ns)
    
    // 等待 socket 可写
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
    
    // Socket 已就绪，进行写操作
    let nwritten, errno = sys_write(s.fd, &buf[0], len(buf))
    if errno != 0 {
        if IsTemporaryError(errno) {
            return 0, nil  // 临时错误，重试
        }
        return 0, NewSocketError(errno, "write")
    }
    
    nwritten, nil
}

// ============================================================================
// 超时处理
// ============================================================================

// 设置读超时截止期限
func (s *RawSocket) SetReadDeadline(deadline_ns: i64) error {
    s.read_deadline_ns = deadline_ns
    nil
}

// 设置写超时截止期限
func (s *RawSocket) SetWriteDeadline(deadline_ns: i64) error {
    s.write_deadline_ns = deadline_ns
    nil
}

// 计算剩余的 poll 超时（毫秒）
// 返回 -1 表示无限期等待，0 表示已过期，正数表示剩余毫秒数
func calculate_timeout_ms(deadline_ns: i64) int {
    if deadline_ns == 0 {
        return -1  // 无限期等待
    }
    
    let now_ns = time.now_ns()  // 获取当前时间（纳秒）
    
    if now_ns >= deadline_ns {
        return 0  // 已过期
    }
    
    let remaining_ns = deadline_ns - now_ns
    let remaining_ms = remaining_ns / 1_000_000  // 转换为毫秒
    
    if remaining_ms > 2147483647 {  // int32 最大值
        2147483647
    } else if remaining_ms < 1 {
        1
    } else {
        remaining_ms  // 返回毫秒
    }
}

// ============================================================================
// Socket 选项
// ============================================================================

// 设置 SO_REUSEADDR 选项（允许地址重用）
func (s *RawSocket) SetReuseAddr(on: bool) error {
    let val: int = if on { 1 } else { 0 }
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_REUSEADDR, (*byte)(&val), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

// 设置 SO_REUSEPORT 选项（允许端口重用）
func (s *RawSocket) SetReusePort(on: bool) error {
    let val: int = if on { 1 } else { 0 }
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_REUSEPORT, (*byte)(&val), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

// 设置 TCP_NODELAY（禁用 Nagle 算法）
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

// 设置发送缓冲区大小
func (s *RawSocket) SetSendBufferSize(size: int) error {
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_SNDBUF, (*byte)(&size), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

// 设置接收缓冲区大小
func (s *RawSocket) SetRecvBufferSize(size: int) error {
    let errno = sys_setsockopt(s.fd, SOL_SOCKET, SO_RCVBUF, (*byte)(&size), 4)
    if errno != 0 {
        return NewSocketError(errno, "setsockopt")
    }
    nil
}

// ============================================================================
// 地址信息
// ============================================================================

// 获取 socket 本地地址
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
    
    // 返回地址字符串和端口
    // TODO: 实现 IPv4 地址转字符串
    "", ntohs(addr.sin_port), nil
}

// 获取 socket 远程地址
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

// ============================================================================
// 辅助函数
// ============================================================================

// 网络字节序转换（反向）
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
