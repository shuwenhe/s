package src.net

// PacketConn 接口，参照 Go net 包
interface PacketConn {
    ReadFrom([]byte) (int, Addr, error)
    WriteTo([]byte, Addr) (int, error)
    Close() error
    LocalAddr() Addr
    SetDeadline(int64) error
    SetReadDeadline(int64) error
    SetWriteDeadline(int64) error
}
