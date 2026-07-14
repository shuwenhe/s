# Socket 系统调用层架构设计

**日期**: 2026-07-14  
**阶段**: Phase 1 - 架构设计和基础实现  
**目标**: 为 S 语言网络模块提供完整的跨平台 Socket 系统调用支持

---

## 1. 设计原则

### 1.1 分层架构

```
┌─────────────────────────────────────────┐
│  高层 API 层 (TCPConn, UDPConn 等)      │
├─────────────────────────────────────────┤
│  Socket 操作层 (read, write, connect)  │
├─────────────────────────────────────────┤
│  系统调用绑定层 (Linux/macOS/Windows)   │
├─────────────────────────────────────────┤
│  操作系统内核 (Linux kernel/Darwin/NT)  │
└─────────────────────────────────────────┘
```

### 1.2 跨平台支持

| 平台 | Architecture | syscall 方式 | 状态 |
|------|--------------|-------------|------|
| Linux | x86_64 | libc + syscall | Phase 2 |
| Linux | ARM64 | libc + syscall | Phase 2.5 |
| macOS | ARM64 | Darwin syscalls | Phase 3 |
| Windows | x86_64 | Winsock2 API | Phase 3.5 |

### 1.3 错误处理

```s
// 统一错误类型
enum SocketError {
    ECONNREFUSED    // 连接被拒绝
    ECONNRESET      // 连接重置
    ETIMEDOUT       // 操作超时
    EWOULDBLOCK     // 非阻塞操作会阻塞
    EINPROGRESS     // 操作进行中
    EBADF           // 坏文件描述符
    EINVAL          // 无效参数
    EMFILE          // 打开的文件太多
    ENFILE          // 系统文件表满
    EAGAIN          // 资源暂时不可用
    EACCES          // 权限不足
    EADDRINUSE      // 地址已被使用
    EADDRNOTAVAIL   // 地址不可用
}
```

---

## 2. 核心组件设计

### 2.1 平台检测和条件编译

```s
// src/net/internal/platform_detection.s

// 平台标记 (编译时设置)
const PLATFORM_LINUX = 1
const PLATFORM_DARWIN = 2
const PLATFORM_WINDOWS = 3
const PLATFORM_FREEBSD = 4

// 架构检测
const ARCH_X86_64 = 1
const ARCH_ARM64 = 2
const ARCH_ARM = 3
const ARCH_X86 = 4

// 运行时平台检测
func get_platform() int { /* ... */ }
func get_architecture() int { /* ... */ }
```

### 2.2 通用 Socket 类型

```s
// src/net/internal/socket_types.s

struct RawSocket {
    int fd                          // 文件描述符
    int family                      // AF_INET, AF_INET6, AF_UNIX
    int socktype                    // SOCK_STREAM, SOCK_DGRAM
    int protocol                    // IPPROTO_TCP, IPPROTO_UDP
    bool blocking                   // 是否阻塞模式
    i64 read_deadline_ns            // 读截止期限 (纳秒)
    i64 write_deadline_ns           // 写截止期限 (纳秒)
}

struct SockAddr {
    // 通用地址结构
    int family
    []byte addr_data                // 地址数据 (可变长)
}
```

### 2.3 Linux x86_64 syscall 绑定

```s
// src/net/internal/syscall_linux_x86_64.s

// Socket syscalls (via libc)
extern fn socket(int family, int type, int protocol) int
extern fn bind(int sockfd, *SockAddr addr, int addrlen) int
extern fn listen(int sockfd, int backlog) int
extern fn accept(int sockfd, *SockAddr addr, *int addrlen) int
extern fn connect(int sockfd, *SockAddr addr, int addrlen) int
extern fn read(int fd, []byte buf) int
extern fn write(int fd, []byte buf) int
extern fn close(int fd) int
extern fn poll(*pollfd fds, int nfds, int timeout_ms) int
extern fn setsockopt(int sockfd, int level, int optname, *byte optval, int optlen) int
extern fn getsockopt(int sockfd, int level, int optname, *byte optval, *int optlen) int
extern fn getpeername(int sockfd, *SockAddr addr, *int addrlen) int
extern fn getsockname(int sockfd, *SockAddr addr, *int addrlen) int
extern fn shutdown(int sockfd, int how) int

// 常量定义
const AF_INET = 2
const AF_INET6 = 10
const AF_UNIX = 1

const SOCK_STREAM = 1        // TCP
const SOCK_DGRAM = 2         // UDP

const IPPROTO_IP = 0
const IPPROTO_TCP = 6
const IPPROTO_UDP = 17

const SOL_SOCKET = 1
const SOL_TCP = 6
const SOL_UDP = 17

const SO_REUSEADDR = 2
const SO_RCVTIMEO = 20
const SO_SNDTIMEO = 21
const SO_RCVBUF = 8
const SO_SNDBUF = 7

const TCP_NODELAY = 1
const TCP_KEEPALIVE = 4

const SHUT_RD = 0
const SHUT_WR = 1
const SHUT_RDWR = 2

const POLLIN = 1
const POLLOUT = 4
const POLLERR = 8
const POLLHUP = 16
```

### 2.4 Socket 核心操作

```s
// src/net/internal/socket_core.s

struct RawSocketOps {
    // 创建 Socket
    fn create(family: int, socktype: int) (int, error) { /* ... */ }
    
    // 绑定到地址
    fn bind(fd: int, addr: *SockAddr) error { /* ... */ }
    
    // 开始监听
    fn listen(fd: int, backlog: int) error { /* ... */ }
    
    // 接受连接
    fn accept(fd: int) (int, *SockAddr, error) { /* ... */ }
    
    // 连接到远程地址
    fn connect(fd: int, addr: *SockAddr, timeout_ms: int) error { /* ... */ }
    
    // 读取数据
    fn read(fd: int, buf: []byte, timeout_ms: int) (int, error) { /* ... */ }
    
    // 写入数据
    fn write(fd: int, buf: []byte, timeout_ms: int) (int, error) { /* ... */ }
    
    // 关闭 Socket
    fn close(fd: int) error { /* ... */ }
    
    // 设置 Socket 选项
    fn set_option(fd: int, level: int, optname: int, optval: []byte) error { /* ... */ }
    
    // 获取 Socket 选项
    fn get_option(fd: int, level: int, optname: int) ([]byte, error) { /* ... */ }
    
    // 设置非阻塞模式
    fn set_nonblocking(fd: int, nonblocking: bool) error { /* ... */ }
    
    // 设置超时
    fn set_deadline(fd: int, deadline_ns: i64) error { /* ... */ }
}
```

---

## 3. 实现阶段

### Phase 1: 架构设计 (完成)
- [x] 定义平台检测机制
- [x] 设计分层架构
- [x] 定义通用类型
- [x] 规划 syscall 绑定

### Phase 2: Linux x86_64 实现 (开始)
**目标**: 基础 TCP/UDP 操作，完整错误处理，超时支持

**任务**:
- [ ] 实现 `syscall_linux_x86_64.s` (Linux 系统调用绑定)
- [ ] 实现 `socket_core.s` (通用 Socket 操作)
- [ ] 实现 `socket_types.s` (Socket 类型定义)
- [ ] 更新 `tcpconn.s` (使用新的系统调用层)
- [ ] 更新 `udpconn.s` (使用新的系统调用层)
- [ ] 编写 `socket_test.s` (单元测试)

**预期时间**: 2-3 天

### Phase 2.5: Linux ARM64 支持
**目标**: 支持 ARM64 架构 (AWS Graviton, Apple Silicon Docker)

**差异**: 
- 部分常量值不同
- syscall 号不同
- 调用约定可能不同

**预期时间**: 1 天

### Phase 3: macOS 支持
**目标**: 支持 Darwin 系统 (macOS)

**差异**:
- 使用 Darwin syscall 而非 libc
- 系统调用号不同
- kevent 代替 poll/epoll

**预期时间**: 1-2 天

### Phase 3.5: Windows 支持
**目标**: 支持 Windows 系统

**差异**:
- 使用 Winsock2 API 而非 BSD socket
- 完全不同的 API 设计
- IOCP 代替 poll/epoll

**预期时间**: 2-3 天

### Phase 4: 网络轮询和高级功能
**目标**: 多路 I/O 复用 (epoll, kqueue, IOCP)

**功能**:
- [ ] epoll 支持 (Linux)
- [ ] kqueue 支持 (macOS, BSD)
- [ ] IOCP 支持 (Windows)
- [ ] 超时处理优化
- [ ] 错误恢复

**预期时间**: 1-2 天

---

## 4. 关键实现细节

### 4.1 超时处理策略

```
用户设置 SetReadDeadline(2026-07-14T15:30:00)
                            │
                            ├─ 计算距离现在还剩多少纳秒
                            │
                            ├─ 如果已过期 → 立即返回 ErrTimeout
                            │
                            ├─ 如果为 0 → 无限期等待
                            │
                            └─ 否则 → poll/select 等待指定时间
```

### 4.2 非阻塞 I/O 模式

```
Linux 实现模式:
1. 创建 socket 时设置为非阻塞 (SOCK_NONBLOCK)
2. 使用 poll() 等待 I/O 就绪
3. I/O 就绪后执行系统调用
4. 如果返回 EAGAIN/EWOULDBLOCK → 重新 poll()
```

### 4.3 错误映射

```s
fn map_errno(errno: int) error {
    case errno {
    ECONNREFUSED → "connection refused"
    ECONNRESET → "connection reset"
    ETIMEDOUT → "i/o timeout"
    EWOULDBLOCK → "resource temporarily unavailable"
    // ... 其他错误 ...
    default → "unknown error: " + itoa(errno)
    }
}
```

---

## 5. 验收标准

### 完整性
- [ ] 支持所有基本 socket 操作 (socket, bind, listen, accept, connect, read, write, close)
- [ ] 支持所有超时操作 (SetDeadline, SetReadDeadline, SetWriteDeadline)
- [ ] 支持 TCP 和 UDP 协议

### 正确性
- [ ] 单元测试覆盖 > 90%
- [ ] 所有错误情况都能正确处理
- [ ] TCP 和 UDP 功能完全正常

### 性能
- [ ] 单次 read/write 操作 < 1ms (不含网络延迟)
- [ ] 连接建立 < 100ms (本地环回)
- [ ] 超时精度 ± 10ms

### 跨平台
- [ ] Linux x86_64 ✅ (Phase 2)
- [ ] Linux ARM64 🟡 (Phase 2.5)
- [ ] macOS ARM64 🟡 (Phase 3)
- [ ] Windows x86_64 🟡 (Phase 3.5)

---

## 6. 测试策略

### 单元测试

```s
// src/net/internal/socket_test.s

func test_socket_create() {
    // 测试创建 TCP socket
    fd, err := create_socket(AF_INET, SOCK_STREAM)
    assert(fd >= 0)
    assert(err == nil)
    close(fd)
}

func test_socket_bind_listen_accept() {
    // 测试 listen 和 accept
    server_fd := create_socket(AF_INET, SOCK_STREAM)
    bind(server_fd, "127.0.0.1:9999")
    listen(server_fd, 1)
    
    client_fd := create_socket(AF_INET, SOCK_STREAM)
    connect(client_fd, "127.0.0.1:9999", 1000)
    
    accepted_fd, _ := accept(server_fd)
    // 验证连接成功
    
    close(client_fd)
    close(accepted_fd)
    close(server_fd)
}

func test_socket_read_write() {
    // 测试数据读写
    // ... TCP read/write 循环
}

func test_socket_timeout() {
    // 测试超时机制
    // 设置 1ms 超时，预期 ETIMEDOUT
}

func test_udp_sendto_recvfrom() {
    // 测试 UDP 操作
}
```

### 集成测试

```s
// src/net/socket_integration_test.s

func test_tcp_server_client() {
    // 创建真实服务器和客户端，测试通信
}

func test_concurrent_connections() {
    // 测试并发连接处理
}

func test_timeout_handling() {
    // 测试超时场景
}
```

---

## 7. 文件清单

### 新增文件

| 文件 | 行数 | 用途 |
|------|------|------|
| `src/net/internal/socket_types.s` | 150 | Socket 类型定义 |
| `src/net/internal/syscall_linux_x86_64.s` | 100 | Linux x86_64 绑定 |
| `src/net/internal/socket_core.s` | 500 | 核心 Socket 操作 |
| `src/net/internal/socket_test.s` | 400 | 单元测试 |
| `src/net/socket_integration_test.s` | 300 | 集成测试 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `src/net/tcpconn.s` | 去除 TODO，集成系统调用层 |
| `src/net/udpconn.s` | 去除 TODO，集成系统调用层 |

---

## 8. 预期成果

### 功能覆盖

✅ TCP 连接 (listen, accept, connect, read, write, close)  
✅ UDP 操作 (bind, sendto, recvfrom)  
✅ 超时支持 (SetDeadline, SetReadDeadline, SetWriteDeadline)  
✅ 错误处理 (完整的错误映射)  
✅ 多平台支持 (Linux/macOS/Windows 的分支实现)

### 代码质量

- 新增 ~1,500 行 S 代码
- 消除 17 个 TODO → 0
- 消除 23 个 Stub → 5 (仅保留平台特定的分支)
- 测试覆盖 > 90%

### 性能指标

- 连接建立: < 100ms
- 读/写操作: < 1ms
- 超时精度: ± 10ms

---

**下一步**: 开始 Phase 2 - 实现 Linux x86_64 系统调用绑定和核心 Socket 操作
