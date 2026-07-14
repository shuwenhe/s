package src.net

// TCPConn is implemented in socket.s. Keeping this unit preserves the
// historical package layout without defining a second, incompatible type.
func tcpconn_unit_name() string { "src/net/tcpconn" }
func tcpconn_unit_ready() int { 1 }
