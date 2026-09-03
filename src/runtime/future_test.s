package src.runtime

func run_future_machine_test() int {
    machine := future_new(0, 2)
    machine.add_transition(1)
    machine.add_transition(2)
    first := machine.poll()
    if first.ready || first.invalid || first.state != 1 {
        return 1
    }
    second := machine.poll()
    if !second.ready || second.state != 2 {
        return 2
    }
    third := machine.poll()
    if !third.ready || third.polls != 3 {
        return 3
    }
    if machine.wake(1) {
        return 4
    }
    machine.reset(0)
    if machine.poll().state != 1 {
        return 5
    }
    0
}
