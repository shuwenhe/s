package src.runtime
use std.option.option

const runtime_feature_gc = 1
const runtime_feature_scheduler = 2
const runtime_feature_channels = 4
const runtime_feature_stack = 8
const runtime_feature_panic = 16
const runtime_feature_reflect = 32
const runtime_feature_syscall = 64
const runtime_feature_profile = 128
const runtime_feature_race = 256

func runtime_features() int {
    runtime_feature_gc + runtime_feature_scheduler + runtime_feature_channels +
        runtime_feature_stack + runtime_feature_panic + runtime_feature_reflect +
        runtime_feature_syscall + runtime_feature_profile + runtime_feature_race
}

func runtime_gc_alloc(int size, int type_id) int {
    object_id := malloc(size, type_id)
    if object_id >= 0 {
        gc_trigger()
    }
    object_id
}

func runtime_gc_collect() () {
    force_gc()
}

func runtime_schedule_step() bool {
    started := __runtime_nanotime()
    next := find_runnable()
    if next < 0 {
        return false
    }
    run_sroutine(next)
    runtime_profile_record("scheduler.step", __runtime_nanotime() - started)
    true
}

func runtime_spawn(int entry_id, string name) int {
    sroutine_spawn(entry_id, name)
}

func runtime_yield() () {
    sroutine_yield()
}

struct runtime_stack_segment {
    int[] words
    int used
    int previous
}

struct runtime_stack {
    runtime_stack_segment[] segments
    int current
    int limit
}

func runtime_stack_new(int initial_words) runtime_stack {
    if initial_words < 64 {
        initial_words = 64
    }
    first := runtime_stack_segment { words: int[](), used: 0, previous: -1 }
    int i = 0
    for i < initial_words {
        first.words.push(0)
        i = i + 1
    }
    segments := runtime_stack_segment[]()
    segments.push(first)
    runtime_stack { segments: segments, current: 0, limit: initial_words }
}

func runtime_stack_grow(runtime_stack* self, int required_words) bool {
    if required_words <= self.limit {
        return true
    }
    old := self.segments[self.current]
    next_limit := self.limit * 2
    for next_limit < required_words {
        next_limit = next_limit * 2
    }
    next := runtime_stack_segment { words: int[](), used: old.used, previous: self.current }
    int i = 0
    for i < next_limit {
        if i < old.used {
            next.words.push(old.words[i])
        } else {
            next.words.push(0)
        }
        i = i + 1
    }
    self.segments.push(next)
    self.current = len(self.segments) - 1
    self.limit = next_limit
    true
}

func runtime_stack_push(runtime_stack* self, int value) bool {
    if self.segments[self.current].used + 1 > self.limit {
        if !runtime_stack_grow(self, self.segments[self.current].used + 1) {
            return false
        }
    }
    segment := self.segments[self.current]
    segment.words.set(segment.used, value)
    segment.used = segment.used + 1
    self.segments.set(self.current, segment)
    true
}

func runtime_stack_pop(runtime_stack* self) int {
    segment := self.segments[self.current]
    if segment.used == 0 {
        return 0
    }
    segment.used = segment.used - 1
    value := segment.words[segment.used]
    self.segments.set(self.current, segment)
    value
}

struct runtime_defer_record {
    func callback
    bool active
}

struct runtime_panic_state {
    runtime_defer_record[] defers
    string message
    bool panicking
}

func runtime_panic_state_new() runtime_panic_state {
    runtime_panic_state { defers: runtime_defer_record[](), message: "", panicking: false }
}

func runtime_defer_push(runtime_panic_state* self, func callback) () {
    self.defers.push(runtime_defer_record { callback: callback, active: true })
}

func runtime_defer_run(runtime_panic_state* self) () {
    i := len(self.defers) - 1
    for i >= 0 {
        record := self.defers[i]
        if record.active {
            record.callback()
            record.active = false
            self.defers.set(i, record)
        }
        i = i - 1
    }
}

func runtime_panic_begin(runtime_panic_state* self, string message) () {
    self.message = message
    self.panicking = true
    runtime_defer_run(self)
}

func runtime_recover(runtime_panic_state* self) string {
    if !self.panicking {
        return ""
    }
    message := self.message
    self.message = ""
    self.panicking = false
    message
}

struct runtime_type {
    int id
    string name
    int size
    int pointer_words
}

struct runtime_value {
    int address
    runtime_type type
}

func runtime_type_of(int id, string name, int size, int pointer_words) runtime_type {
    runtime_type { id: id, name: name, size: size, pointer_words: pointer_words }
}

func runtime_value_assignable(runtime_value value, runtime_type target) bool {
    value.type.id == target.id
}

extern "intrinsic" func __syscall0(int nr) int;
extern "intrinsic" func __syscall1(int nr, int a1) int;
extern "intrinsic" func __syscall2(int nr, int a1, int a2) int;
extern "intrinsic" func __syscall3(int nr, int a1, int a2, int a3) int;
extern "intrinsic" func __syscall6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int;

func runtime_syscall0(int nr) int { __syscall0(nr) }
func runtime_syscall1(int nr, int a1) int { __syscall1(nr, a1) }
func runtime_syscall2(int nr, int a1, int a2) int { __syscall2(nr, a1, a2) }
func runtime_syscall3(int nr, int a1, int a2, int a3) int { __syscall3(nr, a1, a2, a3) }
func runtime_syscall6(int nr, int a1, int a2, int a3, int a4, int a5, int a6) int {
    __syscall6(nr, a1, a2, a3, a4, a5, a6)
}

struct runtime_profile_sample {
    string name
    int count
    int nanos
}

var runtime_profile_samples = runtime_profile_sample[]()
var runtime_profile_enabled = false

func runtime_profile_start() () { runtime_profile_enabled = true }
func runtime_profile_stop() () { runtime_profile_enabled = false }

func runtime_profile_record(string name, int nanos) () {
    if !runtime_profile_enabled {
        return
    }
    int i = 0
    for i < len(runtime_profile_samples) {
        if runtime_profile_samples[i].name == name {
            sample := runtime_profile_samples[i]
            sample.count = sample.count + 1
            sample.nanos = sample.nanos + nanos
            runtime_profile_samples.set(i, sample)
            return
        }
        i = i + 1
    }
    runtime_profile_samples.push(runtime_profile_sample { name: name, count: 1, nanos: nanos })
}

func runtime_profile_snapshot() runtime_profile_sample[] {
    runtime_profile_samples
}

extern "intrinsic" func __race_read(int address, int size) ();
extern "intrinsic" func __race_write(int address, int size) ();

func runtime_race_read(int address, int size) () { __race_read(address, size) }
func runtime_race_write(int address, int size) () { __race_write(address, size) }

func runtime_foundation_unit_name() string { "src/runtime/runtime_foundation" }
func runtime_foundation_unit_ready() int { 1 }
