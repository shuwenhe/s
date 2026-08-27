package test.runtime.sroutine_abi

func abi_worker(int done_channel) int {
    chan_send(done_channel, __sroutine_current_id());
    return 0;
}

func main() {
    if __sroutine_abi_version() != 1 {
        println("FAIL: sroutine ABI version");
        return 1;
    }
    if __sroutine_current_id() != 0 {
        println("FAIL: main sroutine id");
        return 2;
    }
    done_channel := chan_make(2);
    sroutine abi_worker(done_channel);
    sroutine abi_worker(done_channel);
    first := chan_recv(done_channel);
    second := chan_recv(done_channel);
    if first <= 0 || second <= 0 || first == second {
        println("FAIL: worker sroutine id");
        return 3;
    }
    if sroutine_count() != 0 {
        println("FAIL: sroutine count");
        return 4;
    }
    println("PASS: sroutine ABI");
    return 0;
}
