package src.runtime

const SROUTINE_ABI_VERSION = 1

const SROUTINE_IDLE     = 0
const SROUTINE_RUNNABLE = 1
const SROUTINE_RUNNING  = 2
const SROUTINE_WAITING  = 3
const SROUTINE_DEAD     = 4

const SROUTINE_PARK_NONE    = 0
const SROUTINE_PARK_CHANNEL = 1
const SROUTINE_PARK_NETPOLL = 2
const SROUTINE_PARK_TIMER   = 3
const SROUTINE_PARK_JOIN    = 4

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
    __sroutine_abi_version() == SROUTINE_ABI_VERSION
}

func sroutine_state_can_transition(int from, int to) bool {
    if from == SROUTINE_IDLE {
        return to == SROUTINE_RUNNABLE
    }
    if from == SROUTINE_RUNNABLE {
        return to == SROUTINE_RUNNING || to == SROUTINE_DEAD
    }
    if from == SROUTINE_RUNNING {
        return to == SROUTINE_RUNNABLE || to == SROUTINE_WAITING || to == SROUTINE_DEAD
    }
    if from == SROUTINE_WAITING {
        return to == SROUTINE_RUNNABLE || to == SROUTINE_DEAD
    }
    false
}

func sroutine_abi_unit_name() string { "src/runtime/sroutine_abi" }

func sroutine_abi_unit_ready() int { 1 }
