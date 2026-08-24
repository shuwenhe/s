package test.runtime.sroutine

func sroutine_worker(int task_channel, int done_channel, int worker_id) int {
    let task = chan_recv(task_channel);
    chan_send(done_channel, task + worker_id);
    return 0;
}

func main() int {
    let task_channel = chan_make(2);
    let done_channel = chan_make(2);
    sroutine sroutine_worker(task_channel, done_channel, 10);
    sroutine sroutine_worker(task_channel, done_channel, 20);
    chan_send(task_channel, 1);
    chan_send(task_channel, 2);
    let first = chan_recv(done_channel);
    let second = chan_recv(done_channel);
    if first + second != 33 {
        println("FAIL: sroutine runtime");
        return 1;
    }
    println("PASS: sroutine runtime");
    return 0;
}
