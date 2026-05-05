package src.net

// S 语言 socket/IO 伪实现骨架，参照 Go net 包

// Socket 类型常量
const SOCK_STREAM = 1 // TCP
const SOCK_DGRAM  = 2 // UDP

// Address family
const AF_INET  = 2
const AF_INET6 = 10

// 创建 socket
func socket(domain int, typ int, proto int) int {
    // TODO: 调用 S 运行时或 C/Go 扩展实现
    -1
}

// 绑定地址
func bind(fd int, ip string, port int) int {
    // TODO: 封装 sockaddr 结构并绑定
    0
}

// 监听
func listen(fd int, backlog int) int {
    // TODO: listen 系统调用
    0
}

// 接受连接
func accept(fd int) int {
    // TODO: accept 系统调用，返回新 fd
    -1
}

// 连接远端
func connect(fd int, ip string, port int) int {
    // TODO: connect 系统调用
    0
}

// 读数据
func read(fd int, buf []byte) int {
    // TODO: read 系统调用
    0
}

// 写数据
func write(fd int, buf []byte) int {
    // TODO: write 系统调用
    0
}

// 关闭 fd
func close(fd int) int {
    // TODO: close 系统调用
    0
}

// 事件轮询（伪接口，实际需 epoll/select/kqueue 支持）
func poll(fds []int, timeout int) int {
    // TODO: 事件轮询
    0
}
