package src.net
interface conn {
    read(byte[]) (int, error)
    write(byte[]) (int, error)
    close() error
    local_addr() addr
    remote_addr() addr
    set_deadline(int64) error
    set_read_deadline(int64) error
    set_write_deadline(int64) error
}
