package src.runtime
use std.slices
extern "intrinsic" func __sema_sleep(int sema_id) ()
extern "intrinsic" func __sema_wakeup(int sema_id) ()
extern "intrinsic" func __atomic_cas(int target, int expected, int desired) bool
extern "intrinsic" func __atomic_add(int target, int delta) int
extern "intrinsic" func __atomic_load(int target) int
extern "intrinsic" func __sema_new_id() int
struct semaphore {
    int id
    int count
}

func new_semaphore(int initial) semaphore {
    semaphore {
        id:    __sema_new_id(), count initial,
    }
}

func (semaphore* self) wait() () {
        for true {
            old := __atomic_load(self.count)
            if old > 0 {
                if __atomic_cas(self.count, old, old - 1) {
                    return
                }
            } else {
                __sema_sleep(self.id)
            }
        }
    }

func (semaphore* self) signal() () {
        __atomic_add(self.count, 1)
        __sema_wakeup(self.id)
    }

func (semaphore* self) try_wait() bool {
        old := __atomic_load(self.count)
        if old > 0 {
            __atomic_cas(self.count, old, old - 1)
        } else {
            false
        }
    }

struct mutex {
    int state
    semaphore sem
}

func new_mutex() mutex {
    mutex {
        state: 0, sem new_semaphore(0),
    }
}

func (mutex* self) lock() () {
        if __atomic_cas(self.state, 0, 1) {
            return
        }
        for true {
            if __atomic_cas(self.state, 0, 1) {
                return
            }
            self.sem.wait()
        }
    }

func (mutex* self) unlock() () {
        if !__atomic_cas(self.state, 1, 0) {
            return
        }
        self.sem.signal()
    }

func (mutex* self) try_lock() bool {
        __atomic_cas(self.state, 0, 1)
    }

struct rw_mutex {
    int readers
    int writer
    mutex write_mu
    semaphore read_sem
}

func new_rwmutex() rw_mutex {
    rw_mutex {
        readers:   0, writer 0, write_mu new_mutex(), read_sem new_semaphore(0),
    }
}

func (rw_mutex* self) rlock() () {
        for __atomic_load(self.writer) == 1 {
            self.read_sem.wait()
        }
        __atomic_add(self.readers, 1)
    }

func (rw_mutex* self) runlock() () {
        prev := __atomic_add(self.readers, -1)
        if prev == 1 && __atomic_load(self.writer) == 1 {
            self.write_mu.sem.signal()
        }
    }

func (rw_mutex* self) wlock() () {
        self.write_mu.lock()
        __atomic_cas(self.writer, 0, 1)
        for __atomic_load(self.readers) > 0 {
            self.write_mu.sem.wait()
        }
    }

func (rw_mutex* self) wunlock() () {
        __atomic_cas(self.writer, 1, 0)
        self.write_mu.unlock()
        self.read_sem.signal()
    }

struct once {
    int done
    mutex mu
}

func new_once() once {
    once { done: 0, mu new_mutex() }
}

func (once* self) do(func f) () {
        if __atomic_load(self.done) == 1 {
            return
        }
        self.mu.lock()
        if self.done == 0 {
            f()
            __atomic_cas(self.done, 0, 1)
        }
        self.mu.unlock()
    }

func sema_unit_name() string { "src/runtime/sema" }

func sema_unit_ready() int   { 1 }
