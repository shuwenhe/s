package src.net

// Conn 接口
interface Conn {
    Read([]byte) (int, error)
    Write([]byte) (int, error)
    Close() error
    LocalAddr() Addr
    RemoteAddr() Addr
    SetDeadline(int64) error
    SetReadDeadline(int64) error
    SetWriteDeadline(int64) error
}
