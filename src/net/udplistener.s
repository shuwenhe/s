// UDPListener 仅用于接口兼容，UDP 通常无 accept
func (l *UDPListener) Close() error {
    // 实际关闭 UDP fd
    if close(l.fd) != 0 {
        return "close error"
    }
    nil
}

func (l *UDPListener) Addr() Addr {
    &l.laddr
}
package src.net

// UDPListener 结构体（伪实现，UDP 通常无监听，只收发）
struct UDPListener {
    int fd
    UDPAddr laddr
}
