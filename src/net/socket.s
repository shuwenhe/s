package src.net

use src.syscall as sc
use std.result.result
use std.vec.vec
use std.option.option

const AF_INET    = sc.AF_INET
const AF_INET6   = sc.AF_INET6
const SOCK_STREAM = sc.SOCK_STREAM
const SOCK_DGRAM  = sc.SOCK_DGRAM
const POLLIN      = sc.POLLIN
const POLLOUT     = sc.POLLOUT
const POLLERR     = sc.POLLERR

struct net_error {
    string message
    int    errno_code
}

func wrap_sc_err(sc.net_error e) net_error {
    net_error { message: e.message, errno_code: e.errno_code }
}

struct TCPListener {
    int    fd
    string host
    int    port
}

func listen_tcp(string host, int port) result[TCPListener, net_error] {
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_STREAM, sc.IPPROTO_TCP)
    let fd = switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }

    switch sc.set_reuseaddr(fd) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    switch sc.bind(fd, host, port, sc.AF_INET) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    switch sc.listen(fd, 128) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    result::ok(TCPListener { fd: fd, host: sc.local_ip(fd), port: sc.local_port(fd) })
}

func (self: TCPListener) accept() result[TCPConn, net_error] {
        let res = sc.accept_addr(self.fd)
        switch res {
            result::ok(ar)  : result::ok(TCPConn {
                fd:        ar.fd,
                remote_ip: ar.ip,
                remote_port: ar.port,
                read_timeout_ms: 0,
                write_timeout_ms: 0,
            }),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPListener) set_nonblocking() result[(), net_error] {
        switch sc.set_nonblocking(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPListener) close() result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

struct TCPConn {
    int    fd
    string remote_ip
    int    remote_port
    int    read_timeout_ms
    int    write_timeout_ms
}

func dial_tcp(string host, int port) result[TCPConn, net_error] {
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_STREAM, sc.IPPROTO_TCP)
    let fd = switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }

    sc.set_tcp_nodelay(fd)

    switch sc.connect(fd, host, port, sc.AF_INET) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }

    result::ok(TCPConn {
        fd: fd,
        remote_ip: host,
        remote_port: port,
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func dial_tcp_timeout(string host, int port, int timeout_ms) result[TCPConn, net_error] {
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_STREAM, sc.IPPROTO_TCP)
    let fd = switch fd_res {
        result::ok(v) : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.connect_deadline(fd, host, port, sc.AF_INET, timeout_ms) {
        result::ok(_) : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(TCPConn {
        fd: fd,
        remote_ip: sc.peer_ip(fd),
        remote_port: sc.peer_port(fd),
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func dial_tcp6_timeout(string host, int port, int timeout_ms) result[TCPConn, net_error] {
    let fd_res = sc.socket(sc.AF_INET6, sc.SOCK_STREAM, sc.IPPROTO_TCP)
    let fd = switch fd_res {
        result::ok(v) : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.connect_deadline(fd, host, port, sc.AF_INET6, timeout_ms) {
        result::ok(_) : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(TCPConn {
        fd: fd,
        remote_ip: sc.peer_ip(fd),
        remote_port: sc.peer_port(fd),
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func resolve_host(string host) result[vec[string], net_error] {
    switch sc.resolve_ip(host, sc.AF_UNSPEC) {
        result::ok(addresses) : result::ok(addresses),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func (self: TCPConn) read(int max_bytes) result[string, net_error] {
        switch sc.read_string(self.fd, max_bytes) {
            result::ok(data) : result::ok(data),
            result::err(e)   : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) write(string data) result[int, net_error] {
        switch sc.write_string(self.fd, data) {
            result::ok(n)  : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) set_nonblocking() result[(), net_error] {
        switch sc.set_nonblocking(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) wait_readable(int timeout_ms) result[bool, net_error] {
        switch sc.poll_ready(self.fd, sc.POLLIN, timeout_ms) {
            result::ok(n)  : result::ok(n > 0),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) wait_writable(int timeout_ms) result[bool, net_error] {
        switch sc.poll_ready(self.fd, sc.POLLOUT, timeout_ms) {
            result::ok(n)  : result::ok(n > 0),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: &mut TCPConn) set_deadline_ms(int timeout_ms) result[(), net_error] {
        switch sc.set_deadline_ms(self.fd, timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: &mut TCPConn) set_read_deadline_ms(int timeout_ms) result[(), net_error] {
        switch sc.set_deadline_ms(self.fd, timeout_ms, self.write_timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: &mut TCPConn) set_write_deadline_ms(int timeout_ms) result[(), net_error] {
        switch sc.set_deadline_ms(self.fd, self.read_timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) shutdown_read() result[(), net_error] {
        switch sc.shutdown(self.fd, sc.SHUT_RD) {
            result::ok(v) : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) shutdown_write() result[(), net_error] {
        switch sc.shutdown(self.fd, sc.SHUT_WR) {
            result::ok(v) : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: TCPConn) close() result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

struct Poller {
    int fd
}

func new_poller() result[Poller, net_error] {
    switch sc.poller_create() {
        result::ok(fd) : result::ok(Poller { fd: fd }),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func (self: Poller) add(int sock_fd, int events) result[(), net_error] {
        switch sc.poller_add(self.fd, sock_fd, events) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: Poller) del(int sock_fd) result[(), net_error] {
        switch sc.poller_del(self.fd, sock_fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: Poller) wait(int max, int timeout_ms) result[vec[int], net_error] {
        switch sc.poller_wait(self.fd, max, timeout_ms) {
            result::ok(fds) : result::ok(fds),
            result::err(e)  : result::err(wrap_sc_err(e)),
        }
    }

func (self: Poller) close() result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

struct UDPConn {
    int    fd
    string local_ip
    int    local_port
    int    read_timeout_ms
    int    write_timeout_ms
}

func listen_udp(string host, int port) result[UDPConn, net_error] {
    let fd_res = sc.socket(sc.AF_INET, sc.SOCK_DGRAM, sc.IPPROTO_UDP)
    let fd = switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.bind(fd, host, port, sc.AF_INET) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(UDPConn {
        fd: fd,
        local_ip: sc.local_ip(fd),
        local_port: sc.local_port(fd),
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func (self: UDPConn) read(int max_bytes) result[string, net_error] {
        switch sc.read_string(self.fd, max_bytes) {
            result::ok(data) : result::ok(data),
            result::err(e)   : result::err(wrap_sc_err(e)),
        }
    }

func (self: UDPConn) write(string data) result[int, net_error] {
        switch sc.write_string(self.fd, data) {
            result::ok(n)  : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: UDPConn) recv_from(int max_bytes) result[sc.recvfrom_result, net_error] {
        switch sc.recvfrom_string(self.fd, max_bytes) {
            result::ok(datagram) : result::ok(datagram),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: UDPConn) send_to(string data, string host, int port) result[int, net_error] {
        switch sc.sendto_string(self.fd, data, host, port, sc.AF_INET) {
            result::ok(n) : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: &mut UDPConn) set_deadline_ms(int timeout_ms) result[(), net_error] {
        switch sc.set_deadline_ms(self.fd, timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: &mut UDPConn) set_read_deadline_ms(int timeout_ms) result[(), net_error] {
        switch sc.set_deadline_ms(self.fd, timeout_ms, self.write_timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: &mut UDPConn) set_write_deadline_ms(int timeout_ms) result[(), net_error] {
        switch sc.set_deadline_ms(self.fd, self.read_timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (self: UDPConn) close() result[(), net_error] {
        switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }
