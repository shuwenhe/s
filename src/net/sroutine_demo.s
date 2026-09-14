package src.net.sroutine_demo
func worker(int task_channel, int done_channel, int worker_id) int {
    task := chan_recv(task_channel);
    println("worker processed task");
    chan_send(done_channel, task + worker_id);
    return 0;
}

func main() {
    task_channel := chan_make(2);
    done_channel := chan_make(2);
    sroutine worker(task_channel, done_channel, 10);
    sroutine worker(task_channel, done_channel, 20);
    chan_send(task_channel, 1);
    chan_send(task_channel, 2);
    first := chan_recv(done_channel);
    second := chan_recv(done_channel);
    if first + second != 33 {
        println("sroutine demo failed");
        return 1;
    }
    println("sroutine demo passed");
    return 0;
}
