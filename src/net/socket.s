package src.net
use src.syscall as sc
use std.result.result
use std.vec.vec
use std.option.option
const af_inet = sc.af_inet
const af_inet6 = sc.af_inet6
const sock_stream = sc.sock_stream
const sock_dgram = sc.sock_dgram
const poll_in = sc.poll_in
const poll_out = sc.poll_out
const poll_err = sc.poll_err

struct net_error {
    string message
    int    errno_code
}

func wrap_sc_err(sc.net_error e) net_error {
    net_error { message: e.message, errno_code: e.errno_code }
}

struct tcp_listener {
    int    fd
    string host
    int    port
}

func listen_tcp(string host, int port) (tcp_listener, net_error) {
    fd_res := sc.socket(af_inet, sock_stream, sc.ipproto_tcp)
    fd := switch fd_res {
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
    switch sc.bind(fd, host, port, af_inet) {
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
    result::ok(tcp_listener { fd: fd, host: sc.local_ip(fd), port: sc.local_port(fd) })
}

func (tcp_listener self) accept() (tcp_conn, net_error) {
    res := sc.accept_addr(self.fd)
        switch res {
            result::ok(ar)  : result::ok(tcp_conn {
                fd:        ar.fd,
                remote_ip: ar.ip,
                remote_port: ar.port,
                read_timeout_ms: 0,
                write_timeout_ms: 0,
            }),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_listener self) set_nonblocking() ((), net_error) {
    switch sc.set_nonblocking(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_listener self) close() ((), net_error) {
    switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

struct tcp_conn {
    int    fd
    string remote_ip
    int    remote_port
    int    read_timeout_ms
    int    write_timeout_ms
}

func dial_tcp(string host, int port) (tcp_conn, net_error) {
    fd_res := sc.socket(af_inet, sock_stream, sc.ipproto_tcp)
    fd := switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    sc.set_tcp_nodelay(fd)
    switch sc.connect(fd, host, port, af_inet) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(tcp_conn {
        fd: fd,
        remote_ip: host,
        remote_port: port,
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func dial_tcp_timeout(string host, int port, int timeout_ms) (tcp_conn, net_error) {
    fd_res := sc.socket(af_inet, sock_stream, sc.ipproto_tcp)
    fd := switch fd_res {
        result::ok(v) : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.connect_deadline(fd, host, port, af_inet, timeout_ms) {
        result::ok(_) : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(tcp_conn {
        fd: fd,
        remote_ip: sc.peer_ip(fd),
        remote_port: sc.peer_port(fd),
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func dial_tcp6_timeout(string host, int port, int timeout_ms) (tcp_conn, net_error) {
    fd_res := sc.socket(af_inet6, sock_stream, sc.ipproto_tcp)
    fd := switch fd_res {
        result::ok(v) : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.connect_deadline(fd, host, port, af_inet6, timeout_ms) {
        result::ok(_) : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(tcp_conn {
        fd: fd,
        remote_ip: sc.peer_ip(fd),
        remote_port: sc.peer_port(fd),
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func resolve_host(string host) (vec[string], net_error) {
    switch sc.resolve_ip(host, sc.af_unspec) {
        result::ok(addresses) : result::ok(addresses),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func (tcp_conn self) read(int max_bytes) (string, net_error) {
    switch sc.read_string(self.fd, max_bytes) {
            result::ok(data) : result::ok(data),
            result::err(e)   : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) write(string data) (int, net_error) {
    switch sc.write_string(self.fd, data) {
            result::ok(n)  : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) set_nonblocking() ((), net_error) {
    switch sc.set_nonblocking(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) wait_readable(int timeout_ms) (bool, net_error) {
    switch sc.poll_ready(self.fd, poll_in, timeout_ms) {
            result::ok(n)  : result::ok(n > 0),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) wait_writable(int timeout_ms) (bool, net_error) {
    switch sc.poll_ready(self.fd, poll_out, timeout_ms) {
            result::ok(n)  : result::ok(n > 0),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn* self) set_deadline_ms(int timeout_ms) ((), net_error) {
        switch sc.set_deadline_ms(self.fd, timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn* self) set_read_deadline_ms(int timeout_ms) ((), net_error) {
        switch sc.set_deadline_ms(self.fd, timeout_ms, self.write_timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn* self) set_write_deadline_ms(int timeout_ms) ((), net_error) {
        switch sc.set_deadline_ms(self.fd, self.read_timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) shutdown_read() ((), net_error) {
    switch sc.shutdown(self.fd, sc.shut_rd) {
            result::ok(v) : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) shutdown_write() ((), net_error) {
    switch sc.shutdown(self.fd, sc.shut_wr) {
            result::ok(v) : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (tcp_conn self) close() ((), net_error) {
    switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

struct poller {
    int fd
}

func new_poller() (poller, net_error) {
    switch sc.poller_create() {
        result::ok(fd) : result::ok(poller { fd: fd }),
        result::err(e) : result::err(wrap_sc_err(e)),
    }
}

func (poller self) add(int sock_fd, int events) ((), net_error) {
    switch sc.poller_add(self.fd, sock_fd, events) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (poller self) del(int sock_fd) ((), net_error) {
    switch sc.poller_del(self.fd, sock_fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (poller self) wait(int max, int timeout_ms) (vec[int], net_error) {
    switch sc.poller_wait(self.fd, max, timeout_ms) {
            result::ok(fds) : result::ok(fds),
            result::err(e)  : result::err(wrap_sc_err(e)),
        }
    }

func (poller self) close() ((), net_error) {
    switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

struct udp_conn {
    int    fd
    string local_ip
    int    local_port
    int    read_timeout_ms
    int    write_timeout_ms
}

func listen_udp(string host, int port) (udp_conn, net_error) {
    fd_res := sc.socket(af_inet, sock_dgram, sc.ipproto_udp)
    fd := switch fd_res {
        result::ok(v)  : v,
        result::err(e) : return result::err(wrap_sc_err(e)),
    }
    switch sc.bind(fd, host, port, af_inet) {
        result::ok(_)  : (),
        result::err(e) : {
            sc.close(fd)
            return result::err(wrap_sc_err(e))
        },
    }
    result::ok(udp_conn {
        fd: fd,
        local_ip: sc.local_ip(fd),
        local_port: sc.local_port(fd),
        read_timeout_ms: 0,
        write_timeout_ms: 0,
    })
}

func (udp_conn self) read(int max_bytes) (string, net_error) {
    switch sc.read_string(self.fd, max_bytes) {
            result::ok(data) : result::ok(data),
            result::err(e)   : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn self) write(string data) (int, net_error) {
    switch sc.write_string(self.fd, data) {
            result::ok(n)  : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn self) recv_from(int max_bytes) (sc.recvfrom_result, net_error) {
    switch sc.recvfrom_string(self.fd, max_bytes) {
            result::ok(datagram) : result::ok(datagram),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn self) send_to(string data, string host, int port) (int, net_error) {
    switch sc.sendto_string(self.fd, data, host, port, af_inet) {
            result::ok(n) : result::ok(n),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn* self) set_deadline_ms(int timeout_ms) ((), net_error) {
        switch sc.set_deadline_ms(self.fd, timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn* self) set_read_deadline_ms(int timeout_ms) ((), net_error) {
        switch sc.set_deadline_ms(self.fd, timeout_ms, self.write_timeout_ms) {
            result::ok(v) : {
                self.read_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn* self) set_write_deadline_ms(int timeout_ms) ((), net_error) {
        switch sc.set_deadline_ms(self.fd, self.read_timeout_ms, timeout_ms) {
            result::ok(v) : {
                self.write_timeout_ms = timeout_ms
                result::ok(v)
            },
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }

func (udp_conn self) close() ((), net_error) {
    switch sc.close(self.fd) {
            result::ok(v)  : result::ok(v),
            result::err(e) : result::err(wrap_sc_err(e)),
        }
    }
