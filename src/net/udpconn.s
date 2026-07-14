package src.net

// UDPConn is implemented in socket.s. Keeping this unit preserves the
// historical package layout without defining a second, incompatible type.
func udpconn_unit_name() string { "src/net/udpconn" }
func udpconn_unit_ready() int { 1 }
