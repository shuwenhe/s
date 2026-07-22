package src.net

interface PacketConn {
    ReadFrom([]byte) (int, Addr, error)
    WriteTo([]byte, Addr) (int, error)
    Close() error
    LocalAddr() Addr
    SetDeadline(int64) error
    SetReadDeadline(int64) error
    SetWriteDeadline(int64) error
}
