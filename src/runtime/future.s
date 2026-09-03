package src.runtime

struct future_poll {
    bool ready
    bool invalid
    int state
    int polls
}

struct future_machine {
    int state
    int ready_state
    int[] transitions
    int polls
    bool completed
}

func future_new(int initial_state, int ready_state) future_machine {
    future_machine {
        state: initial_state,
        ready_state: ready_state,
        transitions: int[] {},
        polls: 0,
        completed: false,
    }
}

// Add one state transition. A negative target represents a pending state.
func (machine* future_machine) add_transition(int next_state) int {
    if machine.completed {
        return -1
    }
    machine.transitions.push(next_state)
    len(machine.transitions) - 1
}

func (machine* future_machine) poll() future_poll {
    machine.polls = machine.polls + 1
    if machine.completed || machine.state == machine.ready_state {
        machine.completed = true
        return future_poll { ready: true, invalid: false, state: machine.state, polls: machine.polls }
    }
    if machine.state < 0 || machine.state >= len(machine.transitions) {
        return future_poll { ready: false, invalid: true, state: machine.state, polls: machine.polls }
    }
    next_state := machine.transitions[machine.state]
    if next_state < 0 {
        return future_poll { ready: false, invalid: false, state: machine.state, polls: machine.polls }
    }
    machine.state = next_state
    if machine.state == machine.ready_state {
        machine.completed = true
        return future_poll { ready: true, invalid: false, state: machine.state, polls: machine.polls }
    }
    future_poll { ready: false, invalid: false, state: machine.state, polls: machine.polls }
}

func (machine* future_machine) wake(int next_state) bool {
    if machine.completed || next_state < 0 {
        return false
    }
    machine.state = next_state
    true
}

func (machine* future_machine) reset(int initial_state) bool {
    machine.state = initial_state
    machine.polls = 0
    machine.completed = false
    true
}
