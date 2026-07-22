package src.net

func parse_ip_port(addr string) (string, int) {
    parts = split(addr, ":")
    if len(parts) != 2 {
        return "", 0
    }
    ip = parts[0]
    port = atoi(parts[1])
    ip, port
}

func split_host_port(addr string) (string, string) {
    parts = split(addr, ":")
    if len(parts) != 2 {
        return "", ""
    }
    parts[0], parts[1]
}
