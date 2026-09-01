package test.runtime.sroutine_deadlock
func main() {
    channel := chan_make(1);
    chan_recv(channel);
    return 0;
}
