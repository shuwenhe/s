package src.net

// Listen 伪实现
// Listen 支持 "tcp"/"udp"，返回对应 Listener
func Listen(network string, address string) Listener {
    // 解析 address
    parts = split(address, ":")
    ip = parts[0]
    port = atoi(parts[1])
    if network == "tcp" {
        fd = socket(AF_INET, SOCK_STREAM, 0)
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
        TCPListener l = TCPListener { fd: fd, laddr: TCPAddr { ip: ip, port: port } }
        &l
    } else if network == "udp" {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 {
            return nil
        }
        if bind(fd, ip, port) != 0 {
            close(fd)
            return nil
        }
        UDPListener l = UDPListener { fd: fd, laddr: UDPAddr { ip: ip, port: port } }
        &l
    } else {
        nil
    }
}
}
