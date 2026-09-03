package src.syscall

import (
	"src/unsafe"
)

const (
	o_rdonly = 0x0
	o_wronly = 0x1
	o_rdwr = 0x2
	o_creat = 0x40
	o_excl = 0x80
	o_trunc = 0x200
	o_append = 0x400
	o_nonblock = 0x800
	o_sync = 0x1000
)

const (
	seek_set = 0
	seek_cur = 1
	seek_end = 2
)

enum errno {
	eperm = 1
	enoent = 2
	esrch = 3
	eintr = 4
	eio = 5
	enxio = 6
	e2big = 7
	enoexec = 8
	ebadf = 9
	echild = 10
	eagain = 11
	enomem = 12
	eacces = 13
	efault = 14
	enotblk = 15
	ebusy = 16
	eexist = 17
	exdev = 18
	enodev = 19
	enotdir = 20
	eisdir = 21
	einval = 22
	enfile = 23
	emfile = 24
	enotty = 25
	etxtbsy = 26
	efbig = 27
	enospc = 28
	espipe = 29
	erofs = 30
}

struct stat {
	dev u64
	ino u64
	nlink u64
	mode u32
	uid u32
	gid u32
	rdev u64
	size i64
	blksize i64
	blocks i64
	atime_sec i64
	atime_nsec i64
	mtime_sec i64
	mtime_nsec i64
	ctime_sec i64
	ctime_nsec i64
}

struct timespec {
	sec i64
	nsec i64
}

struct timeval {
	sec i64
	usec i64
}

func open(path string, flags i32, mode i32) (i32, error) {
	return 0, nil
}

func close(fd i32) error {
	return nil
}

func read(fd i32, buf u8[]) (i32, error) {
	return 0, nil
}

func write(fd i32, buf u8[]) (i32, error) {
	return 0, nil
}

func pread(fd i32, buf u8[], offset i64) (i32, error) {
	return 0, nil
}

func pwrite(fd i32, buf u8[], offset i64) (i32, error) {
	return 0, nil
}

func lseek(fd i32, offset i64, whence i32) (i64, error) {
	return 0, nil
}

func stat(path string) (stat*, error) {
	return nil, nil
}

func fstat(fd i32) (stat*, error) {
	return nil, nil
}

func mkdir(path string, mode i32) error {
	return nil
}

func rmdir(path string) error {
	return nil
}

func remove(path string) error {
	return nil
}

func rename(oldpath string, newpath string) error {
	return nil
}

func chmod(path string, mode i32) error {
	return nil
}

func link(oldpath string, newpath string) error {
	return nil
}

func symlink(oldpath string, newpath string) error {
	return nil
}

func readlink(path string) (string, error) {
	return "", nil
}

func dup(fd i32) (i32, error) {
	return 0, nil
}

func dup2(fd i32, fd2 i32) (i32, error) {
	return 0, nil
}

func pipe() (i32, i32, error) {
	return 0, 0, nil
}

func fork() (i32, error) {
	return 0, nil
}

func exec(path string, args []string) error {
	return nil
}

func wait() (i32, i32, error) {
	return 0, 0, nil
}

func getpid() i32 {
	return 0
}

func getppid() i32 {
	return 0
}

func exit(code i32) {
}

func geteuid() i32 {
	return 0
}

func getuid() i32 {
	return 0
}

func getegid() i32 {
	return 0
}

func getgid() i32 {
	return 0
}

func time() i64 {
	return 0
}

func gettimeofday() (i64, i64, error) {
	return 0, 0, nil
}

func nanosleep(req timespec*) (timespec*, error) {
	return nil, nil
}

func fcntl(fd i32, cmd i32, arg i32) (i32, error) {
	return 0, nil
}

func ioctl(fd i32, cmd u32, arg unsafe.pointer) (i32, error) {
	return 0, nil
}

func poll(fds u8[], nfds u32, timeout i32) (i32, error) {
	return 0, nil
}

func socket(family i32, type_n i32, proto i32) (i32, error) {
	return 0, nil
}

func bind(sockfd i32, addr u8[], addrlen i32) error {
	return nil
}

func listen(sockfd i32, backlog i32) error {
	return nil
}

func accept(sockfd i32) (i32, error) {
	return 0, nil
}

func connect(sockfd i32, addr u8[], addrlen i32) error {
	return nil
}

func send(sockfd i32, buf u8[]) (i32, error) {
	return 0, nil
}

func recv(sockfd i32, buf u8[]) (i32, error) {
	return 0, nil
}

func sendto(sockfd i32, buf u8[], addr u8[]) (i32, error) {
	return 0, nil
}

func recvfrom(sockfd i32, buf u8[]) (i32, error) {
	return 0, nil
}

func shutdown(sockfd i32, how i32) error {
	return nil
}

func gethostname() (string, error) {
	return "", nil
}

func getaddrinfo(host string, service string) (u8[], error) {
	return nil, nil
}

func getnameinfo(addr u8[]) (string, error) {
	return "", nil
}
