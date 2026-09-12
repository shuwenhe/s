package src.runtime

import (
	"src/sync"
	"src/sync/atomic"
	"src/time"
)

enum race_type {
	race_read = 0
	race_write = 1
	race_write_write = 2
	race_read_write = 3
}

struct race_event {
	u64 addr
	u64 g_id
	race_type event_type
	i64 timestamp
	string[] stack_trace
	bool is_write
}

struct race_detector {
	bool enabled
	race_event[] events
	map[u64]race_event[] addr_map
	sync.rwmutex lock
	i32 race_count
	bool stop_on_race
}

var global_race_detector race_detector

func race_detector_init() error {
	global_race_detector.enabled = true
	global_race_detector.events = make(race_event[], 0)
	global_race_detector.addr_map = make(map[u64]race_event[])
	global_race_detector.race_count = 0
	global_race_detector.stop_on_race = false
	nil
}

func race_record_access(addr u64, bool is_write) {
	if !global_race_detector.enabled {
		return
	}

	g_id := get_current_sroutine_id()
	timestamp := time.now_ns()

	event := race_event{
		addr: addr,
		g_id: g_id,
		event_type: i32(select(is_write, race_write, race_read)),
		timestamp: timestamp,
		stack_trace: capture_stack_trace(),
		is_write: is_write,
	}

	global_race_detector.lock.lock()
	defer global_race_detector.lock.unlock()

	if prev_events, ok := global_race_detector.addr_map[addr]; ok {
		if check_race_condition(prev_events, event) {
			global_race_detector.race_count += 1

			if global_race_detector.stop_on_race {
				report_race(addr, prev_events[len(prev_events)-1], event)
				panic_impl("race condition detected")
			}
		}
	}

	global_race_detector.events = append(global_race_detector.events, event)
	global_race_detector.addr_map[addr] = append(global_race_detector.addr_map[addr], event)
}

func check_race_condition(prev_events race_event[], current race_event) bool {
	if len(prev_events) == 0 {
		return false
	}

	last_event := prev_events[len(prev_events)-1]

	if last_event.g_id != current.g_id {
		if last_event.is_write || current.is_write {
			return true
		}
	}

	return false
}

func report_race(addr u64, event1 race_event, event2 race_event) {
	fmt.fprintf(fmt.stderr, "race detected on addr 0x%x\n", addr)
	fmt.fprintf(fmt.stderr, "event 1: g%d %s at %d\n", event1.g_id, event1_type_str(event1.event_type), event1.timestamp)
	fmt.fprintf(fmt.stderr, "event 2: g%d %s at %d\n", event2.g_id, event2_type_str(event2.event_type), event2.timestamp)
}

func event1_type_str(t race_type) string {
	match t {
	case race_write {
		return "WRITE"
	}
	case race_read {
		return "READ"
	}
	default {
		return "unknown"
	}
	}
}

func event2_type_str(t race_type) string {
	match t {
	case race_write {
		return "WRITE"
	}
	case race_read {
		return "READ"
	}
	default {
		return "unknown"
	}
	}
}

struct profiler {
	bool enabled
	profile_sample[] samples
	i32 current_sample
	i32 max_samples
	i32 sampling_rate
	u64 cpu_samples
	u64 mem_samples
}

struct profile_sample {
	u64 g_id
	u64 pc
	i64 timestamp
	string[] stack_trace
	u64 mem_used
	i64 cpu_time
}

var global_profiler profiler

func profiler_init(rate i32) error {
	global_profiler.enabled = true
	global_profiler.sampling_rate = rate
	global_profiler.max_samples = 100000
	global_profiler.samples = make(profile_sample[], 0)
	global_profiler.current_sample = 0
	nil
}

func profiler_sample(pc u64) {
	if !global_profiler.enabled {
		return
	}

	if atomic.load_i32(&global_profiler.current_sample) % global_profiler.sampling_rate != 0 {
		return
	}

	g_id := get_current_sroutine_id()
	timestamp := time.now_ns()
	stack := capture_stack_trace()

	sample := profile_sample{
		g_id: g_id,
		pc: pc,
		timestamp: timestamp,
		stack_trace: stack,
		mem_used: 0,
		cpu_time: 0,
	}

	if len(global_profiler.samples) < global_profiler.max_samples {
		global_profiler.samples = append(global_profiler.samples, sample)
	}

	atomic.add_i32(&global_profiler.current_sample, 1)
}

struct tracer {
	bool enabled
	trace_event[] events
	i64 start_time
	i64 end_time
	i32 max_events
}

struct trace_event {
	string event_type
	u64 g_id
	i64 timestamp
	i64 duration
	string extra
}

var global_tracer tracer

func tracer_init() error {
	global_tracer.enabled = true
	global_tracer.events = make(trace_event[], 0)
	global_tracer.max_events = 100000
	global_tracer.start_time = time.now_ns()
	nil
}

func tracer_event(string event_type, g_id u64, duration i64, string extra) {
	if !global_tracer.enabled {
		return
	}

	timestamp := time.now_ns()

	evt := trace_event{
		event_type: event_type,
		g_id: g_id,
		timestamp: timestamp,
		duration: duration,
		extra: extra,
	}

	if len(global_tracer.events) < global_tracer.max_events {
		global_tracer.events = append(global_tracer.events, evt)
	}
}

func tracer_sroutine_create(g_id u64) {
	tracer_event("sroutine_create", g_id, 0, "")
}

func tracer_sroutine_start(g_id u64) {
	tracer_event("sroutine_start", g_id, 0, "")
}

func tracer_sroutine_end(g_id u64) {
	tracer_event("sroutine_end", g_id, 0, "")
}

func tracer_channel_send(ch_id u64, g_id u64) {
	tracer_event("channel_send", g_id, 0, fmt_int64(ch_id))
}

func tracer_channel_recv(ch_id u64, g_id u64) {
	tracer_event("channel_recv", g_id, 0, fmt_int64(ch_id))
}

func tracer_lock_acquire(lock_id u64, g_id u64, duration i64) {
	tracer_event("lock_acquire", g_id, duration, fmt_int64(lock_id))
}

func tracer_lock_release(lock_id u64, g_id u64) {
	tracer_event("lock_release", g_id, 0, fmt_int64(lock_id))
}

func tracer_flush() error {
	if !global_tracer.enabled {
		return nil
	}

	global_tracer.end_time = time.now_ns()

	for i := i32(0); i < i32(len(global_tracer.events)); i += 1 {
		event := global_tracer.events[i]
		fmt.fprintf(fmt.stderr, "[%d] %s g%d @ %d (+%d) %s\n",
			i, event.event_type, event.g_id, event.timestamp, event.duration, event.extra)
	}

	nil
}

func fmt_int64(v i64) string {
	return ""
}

func select(bool cond, true_val i32, false_val i32) i32 {
	if cond {
		return true_val
	}
	return false_val
}