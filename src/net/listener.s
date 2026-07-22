package src.net

interface Listener {
    Accept() Conn
    Close() error
    Addr() Addr
}
