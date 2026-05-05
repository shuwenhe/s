package src.net

// Listener 接口
interface Listener {
    Accept() Conn
    Close() error
    Addr() Addr
}
