package src.runtime
const sroutine_abi_version = 1
const sroutine_idle     = 0
const sroutine_runnable = 1
const sroutine_running  = 2
const sroutine_waiting  = 3
const sroutine_dead     = 4
const sroutine_park_none    = 0
const sroutine_park_channel = 1
const sroutine_park_netpoll = 2
const sroutine_park_timer   = 3
const sroutine_park_join    = 4
extern "intrinsic" func __sroutine_abi_version() int
extern "intrinsic" func __sroutine_current_id() int
extern "intrinsic" func __sroutine_stack_create(int sroutine_id, int entry_id, int stack_size) int
extern "intrinsic" func __sroutine_context_switch(int from_sroutine_id, int to_sroutine_id) ()
extern "intrinsic" func __sroutine_stack_destroy(int sroutine_id) ()
extern "intrinsic" func __runtime_num_cpu() int
extern "intrinsic" func __runtime_thread_wake(int thread_id) int
extern "intrinsic" func __runtime_nanotime() int
extern "intrinsic" func __runtime_sleep_briefly() ()
func sroutine_abi_ready() bool {
    __sroutine_abi_version() == sroutine_abi_version
}

func sroutine_state_can_transition(int from, int to) bool {
    if from == sroutine_idle {
        return to == sroutine_runnable
    }
    if from == sroutine_runnable {
        return to == sroutine_running || to == sroutine_dead
    }
    if from == sroutine_running {
        return to == sroutine_runnable || to == sroutine_waiting || to == sroutine_dead
    }
    if from == sroutine_waiting {
        return to == sroutine_runnable || to == sroutine_dead
    }
    false
}

func sroutine_abi_unit_name() string { "src/runtime/sroutine_abi" }

func sroutine_abi_unit_ready() int { 1 }
