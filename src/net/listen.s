package src.net
func listen(network string, address string) listener {
    parts = split(address, ":")
    ip = parts[0]
    port = atoi(parts[1])
    if network == "tcp" {
        fd = socket(af_inet, sock_stream, 0)
        if fd < 0 {
            return nil
        }
        if bind(fd, ip, port) != 0 {
            close(fd)
            return nil
        }
        if listen(fd, 128) != 0 {
            close(fd)
            return nil
        }
        tcp_listener l = tcp_listener { fd: fd, laddr tcp_addr { ip: ip, port port } }
        *l
    } else if network == "udp" {
        fd = socket(af_inet, sock_dgram, 0)
        if fd < 0 {
            return nil
        }
        if bind(fd, ip, port) != 0 {
            close(fd)
            return nil
        }
        udp_listener l = udp_listener { fd: fd, laddr udp_addr { ip: ip, port port } }
        *l
    } else {
        nil
    }
}
}
