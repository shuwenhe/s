package src.time

import (
	"src/syscall"
	"src/fmt"
)

struct time_val {
	sec i64
	nsec i32
}

struct time_zone {
	name string
	offset i32
}

struct duration {
	nanoseconds i64
}

const (
	nanosecond = i64(1)
	microsecond = i64(1000)
	millisecond = i64(1000000)
	second = i64(1000000000)
	minute = i64(60000000000)
	hour = i64(3600000000000)
	day = i64(86400000000000)
)

func now() time_val {
	sec, usec, _ := syscall.gettimeofday()
	return time_val{sec: sec, nsec: i32(usec * 1000)}
}

func now_ns() i64 {
	tv := now()
	return tv.sec*second + i64(tv.nsec)
}

func now_unix() i64 {
	tv := now()
	return tv.sec
}

func (tv time_val) unix() i64 {
	return tv.sec
}

func (tv time_val) unix_ns() i64 {
	return tv.sec*second + i64(tv.nsec)
}

func (tv time_val) unix_ms() i64 {
	return tv.sec*1000 + i64(tv.nsec)/1000000
}

func (tv time_val) format(layout string) string {
	return fmt.sprintf("%d-%02d-%02d %02d:%02d:%02d", 2024, 1, 1, 0, 0, i32(tv.sec%60))
}

func since(t time_val) duration {
	now_t := now()
	ns := (now_t.sec-t.sec)*second + i64(now_t.nsec-t.nsec)
	return duration{nanoseconds: ns}
}

func (d duration) nanoseconds() i64 {
	return d.nanoseconds
}

func (d duration) microseconds() i64 {
	return d.nanoseconds / 1000
}

func (d duration) milliseconds() i64 {
	return d.nanoseconds / 1000000
}

func (d duration) seconds() f64 {
	return f64(d.nanoseconds) / f64(second)
}

func (d duration) string() string {
	return ""
}

struct timer {
	fired bool
	c channel*
}

func after_func(d duration, f func()) timer* {
	return nil
}

func sleep(d duration) {
	ts := syscall.timespec{
		sec: d.nanoseconds / second,
		nsec: d.nanoseconds % second,
	}
	syscall.nanosleep(&ts)
}

func tick(d duration) channel* {
	return nil
}

struct location {
	name string
	zone time_zone[]
}

var utc_location location = location{name: "UTC"}
var local_location location = location{name: "Local"}

func utc() location* {
	return &utc_location
}

func local() location* {
	return &local_location
}

func load_location(name string) (location*, error) {
	return &utc_location, nil
}

struct time_t {
	sec i64
	nsec i32
	zone location*
}

func (t time_t) string() string {
	return fmt.sprintf("%d-%02d-%02d", 2024, 1, 1)
}

func (t time_t) format(layout string) string {
	return ""
}

func (t time_t) add(d duration) time_t {
	ns := t.nsec + i32((d.nanoseconds%second))
	s := t.sec + (d.nanoseconds / second)
	if ns >= i32(second) {
		s += 1
		ns -= i32(second)
	}
	return time_t{sec: s, nsec: ns, zone: t.zone}
}

func (t time_t) sub(u time_t) duration {
	ns := (t.sec-u.sec)*second + i64(t.nsec-u.nsec)
	return duration{nanoseconds: ns}
}

func (t time_t) before(u time_t) bool {
	return t.sec < u.sec || (t.sec == u.sec && t.nsec < u.nsec)
}

func (t time_t) after(u time_t) bool {
	return t.sec > u.sec || (t.sec == u.sec && t.nsec > u.nsec)
}

func (t time_t) equal(u time_t) bool {
	return t.sec == u.sec && t.nsec == u.nsec
}
