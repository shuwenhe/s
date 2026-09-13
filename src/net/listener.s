package src.net
interface listener {
    accept() conn
    close() error
    addr() addr
}
