package src.net
interface packet_conn {
    read_from(byte[]) (int, addr, error)
    write_to(byte[], addr) (int, error)
    close() error
    local_addr() addr
    set_deadline(int64) error
    set_read_deadline(int64) error
    set_write_deadline(int64) error
}
