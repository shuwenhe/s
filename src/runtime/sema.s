package src.runtime

use std.vec.vec

extern "intrinsic" func __sema_sleep(int sema_id) ()
extern "intrinsic" func __sema_wakeup(int sema_id) ()
extern "intrinsic" func __atomic_cas(int mut target, int expected, int desired) bool
extern "intrinsic" func __atomic_add(int mut target, int delta) int
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

func (self: &mut Semaphore) wait() () {
        while true {
            let old = __atomic_load(self.count)
            if old > 0 {
                if __atomic_cas(self.count, old, old - 1) {
                    return
                }
            } else {
                __sema_sleep(self.id)
            }
        }
    }

func (self: &mut Semaphore) signal() () {
        __atomic_add(self.count, 1)
        __sema_wakeup(self.id)
    }

func (self: &mut Semaphore) try_wait() bool {
        let old = __atomic_load(self.count)
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

func (self: &mut Mutex) lock() () {
        if __atomic_cas(self.state, 0, 1) {
            return
        }
        while true {
            if __atomic_cas(self.state, 0, 1) {
                return
            }
            self.sem.wait()
        }
    }

func (self: &mut Mutex) unlock() () {
        if !__atomic_cas(self.state, 1, 0) {
            return
        }
        self.sem.signal()
    }

func (self: &mut Mutex) try_lock() bool {
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

func (self: &mut RWMutex) rlock() () {
        while __atomic_load(self.writer) == 1 {
            self.read_sem.wait()
        }
        __atomic_add(self.readers, 1)
    }

func (self: &mut RWMutex) runlock() () {
        let prev = __atomic_add(self.readers, -1)
        if prev == 1 && __atomic_load(self.writer) == 1 {
            self.write_mu.sem.signal()
        }
    }

func (self: &mut RWMutex) wlock() () {
        self.write_mu.lock()
        __atomic_cas(self.writer, 0, 1)
        while __atomic_load(self.readers) > 0 {
            self.write_mu.sem.wait()
        }
    }

func (self: &mut RWMutex) wunlock() () {
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

func (self: &mut Once) do(func f) () {
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
