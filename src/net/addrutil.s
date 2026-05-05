package src.net

// 解析 host:port 字符串，返回 ip, port
func parse_ip_port(addr string) (string, int) {
    parts = split(addr, ":")
    if len(parts) != 2 {
        return "", 0
    }
    ip = parts[0]
    port = atoi(parts[1])
    ip, port
}

// 拆分 host:port
func split_host_port(addr string) (string, string) {
    parts = split(addr, ":")
    if len(parts) != 2 {
        return "", ""
    }
    parts[0], parts[1]
}
