package src.runtime
use std.slices
extern "intrinsic" func __sema_sleep(int sema_id) ()
extern "intrinsic" func __sema_wakeup(int sema_id) ()
extern "intrinsic" func __atomic_cas(int target, int expected, int desired) bool
extern "intrinsic" func __atomic_add(int target, int delta) int
extern "intrinsic" func __atomic_load(int target) int
extern "intrinsic" func __sema_new_id() int
struct Semaphore {
    int id
    int count
}

func new_semaphore(int initial) Semaphore {
    Semaphore {
        id:    __sema_new_id(),
        count: initial,
    }
}

func (Semaphore* self) wait() () {
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

func (Semaphore* self) signal() () {
        __atomic_add(self.count, 1)
        __sema_wakeup(self.id)
    }

func (Semaphore* self) try_wait() bool {
        old := __atomic_load(self.count)
        if old > 0 {
            __atomic_cas(self.count, old, old - 1)
        } else {
            false
        }
    }

struct Mutex {
    int state
    Semaphore sem
}

func new_mutex() Mutex {
    Mutex {
        state: 0,
        sem:   new_semaphore(0),
    }
}

func (Mutex* self) lock() () {
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

func (Mutex* self) unlock() () {
        if !__atomic_cas(self.state, 1, 0) {
            return
        }
        self.sem.signal()
    }

func (Mutex* self) try_lock() bool {
        __atomic_cas(self.state, 0, 1)
    }

struct RWMutex {
    int readers
    int writer
    Mutex write_mu
    Semaphore read_sem
}

func new_rwmutex() RWMutex {
    RWMutex {
        readers:   0,
        writer:    0,
        write_mu:  new_mutex(),
        read_sem:  new_semaphore(0),
    }
}

func (RWMutex* self) rlock() () {
        for __atomic_load(self.writer) == 1 {
            self.read_sem.wait()
        }
        __atomic_add(self.readers, 1)
    }

func (RWMutex* self) runlock() () {
        prev := __atomic_add(self.readers, -1)
        if prev == 1 && __atomic_load(self.writer) == 1 {
            self.write_mu.sem.signal()
        }
    }

func (RWMutex* self) wlock() () {
        self.write_mu.lock()
        __atomic_cas(self.writer, 0, 1)
        for __atomic_load(self.readers) > 0 {
            self.write_mu.sem.wait()
        }
    }

func (RWMutex* self) wunlock() () {
        __atomic_cas(self.writer, 1, 0)
        self.write_mu.unlock()
        self.read_sem.signal()
    }

struct Once {
    int done
    Mutex mu
}

func new_once() Once {
    Once { done: 0, mu: new_mutex() }
}

func (Once* self) do(func f) () {
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
