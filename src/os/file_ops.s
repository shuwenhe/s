package src.os

import (
	"src/syscall"
)

struct file {
	i32 fd
	string name
}

struct file_error {
	string op
	string path
	error err
}

func (file_error* fe) error() string {
	fe.op + " " + fe.path + ": " + fe.err
}

func open(name string, flags i32, mode i32) (file*, error) {
	fd, err := syscall.open(name, flags, mode)
	if err != nil {
		nil, &file_error{op: "open", path: name, err: err}
	}
	
	f := &file{fd: fd, name: name}
	f, nil
}

func create(name string) (file*, error) {
	flags := syscall.O_WRONLY | syscall.O_CREATE | syscall.O_TRUNC
	mode := i32(0o666)
	fd, err := syscall.open(name, flags, mode)
	if err != nil {
		nil, &file_error{op: "create", path: name, err: err}
	}
	
	f := &file{fd: fd, name: name}
	f, nil
}

func (file* f) read(b u8[]) (i32, error) {
	if f == nil || f.fd < 0 {
		0, &file_error{op: "read", path: f.name, err: "file closed"}
	}
	
	n, err := syscall.read(f.fd, b)
	if err != nil {
		0, &file_error{op: "read", path: f.name, err: err}
	}
	
	n, nil
}

func (file* f) read_at(b u8[], offset i64) (i32, error) {
	if f == nil || f.fd < 0 {
		0, &file_error{op: "read", path: f.name, err: "file closed"}
	}
	
	n, err := syscall.pread(f.fd, b, offset)
	if err != nil {
		0, &file_error{op: "read", path: f.name, err: err}
	}
	
	n, nil
}

func (file* f) write(b u8[]) (i32, error) {
	if f == nil || f.fd < 0 {
		0, &file_error{op: "write", path: f.name, err: "file closed"}
	}
	
	n, err := syscall.write(f.fd, b)
	if err != nil {
		0, &file_error{op: "write", path: f.name, err: err}
	}
	
	n, nil
}

func (file* f) write_at(b u8[], offset i64) (i32, error) {
	if f == nil || f.fd < 0 {
		0, &file_error{op: "write", path: f.name, err: "file closed"}
	}
	
	n, err := syscall.pwrite(f.fd, b, offset)
	if err != nil {
		0, &file_error{op: "write", path: f.name, err: err}
	}
	
	n, nil
}

func (file* f) close() error {
	if f == nil || f.fd < 0 {
		nil
	}
	
	err := syscall.close(f.fd)
	f.fd = -1
	
	if err != nil {
		&file_error{op: "close", path: f.name, err: err}
	}
	
	nil
}

func open(name string) (file*, error) {
	open(name, syscall.O_RDONLY, 0)
}
