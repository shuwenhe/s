// ============================================================
// sema.s — S 运行时同步原语
//
// 提供三层同步原语：
//   1. Semaphore  — 计数信号量（底层，由协程调度器实现）
//   2. Mutex      — 互斥锁（不可重入）
//   3. RWMutex    — 读写锁（多读单写）
//
// 实现策略：
//   • Semaphore 依赖 OS 级原语（futex/pthread_cond）
//   • Mutex/RWMutex 用自旋 + Semaphore 挂起实现
//   • 等待者队列存储 goroutine ID，由调度器唤醒
// ============================================================
package src.runtime

use std.vec.vec

// ─── OS 级同步原语桥接 ────────────────────────────────────────
// 阻塞当前 goroutine，直到信号到来
extern "intrinsic" func __sema_sleep(int sema_id) ()
// 唤醒等待该信号量的一个 goroutine
extern "intrinsic" func __sema_wakeup(int sema_id) ()
// 原子 CAS（compare-and-swap）：返回是否成功
extern "intrinsic" func __atomic_cas(int mut target, int expected, int desired) bool
// 原子递增，返回旧值
extern "intrinsic" func __atomic_add(int mut target, int delta) int
// 原子读
extern "intrinsic" func __atomic_load(int target) int
// 分配新的 sema_id（每个 Semaphore/Mutex 有唯一 ID）
extern "intrinsic" func __sema_new_id() int

// ─── Semaphore（计数信号量）──────────────────────────────────
struct Semaphore {
    int id     // OS 级信号量句柄
    int count  // 当前计数
}

func new_semaphore(int initial) Semaphore {
    Semaphore {
        id:    __sema_new_id(),
        count: initial,
    }
}

impl Semaphore {
    // P 操作（等待/获取）
    func wait(mut self) () {
        while true {
            let old = __atomic_load(self.count)
            if old > 0 {
                if __atomic_cas(self.count, old, old - 1) {
                    return
                }
                // CAS 失败（竞争），重试
            } else {
                // count == 0，挂起当前 goroutine
                __sema_sleep(self.id)
                // 被唤醒后重试
            }
        }
    }

    // V 操作（释放/通知）
    func signal(mut self) () {
        __atomic_add(self.count, 1)
        __sema_wakeup(self.id)
    }

    // 尝试获取（非阻塞），成功返回 true
    func try_wait(mut self) bool {
        let old = __atomic_load(self.count)
        if old > 0 {
            __atomic_cas(self.count, old, old - 1)
        } else {
            false
        }
    }
}

// ─── Mutex（互斥锁）──────────────────────────────────────────
// state: 0 = 未锁，1 = 已锁
struct Mutex {
    int state    // 0=free, 1=locked
    Semaphore sem
}

func new_mutex() Mutex {
    Mutex {
        state: 0,
        sem:   new_semaphore(0),
    }
}

impl Mutex {
    func lock(mut self) () {
        // 快路径：CAS 0 → 1
        if __atomic_cas(self.state, 0, 1) {
            return
        }
        // 慢路径：等待信号量
        while true {
            if __atomic_cas(self.state, 0, 1) {
                return
            }
            self.sem.wait()
        }
    }

    func unlock(mut self) () {
        if !__atomic_cas(self.state, 1, 0) {
            // 未持有锁就解锁：运行时错误（此处简化为忽略）
            return
        }
        self.sem.signal()
    }

    // 非阻塞尝试加锁
    func try_lock(mut self) bool {
        __atomic_cas(self.state, 0, 1)
    }
}

// ─── RWMutex（读写锁）────────────────────────────────────────
// readers > 0  : 有读者持有锁
// writer == 1  : 写者持有锁
struct RWMutex {
    int readers        // 活跃读者数（原子）
    int writer         // 写者等待/持有标记
    Mutex write_mu     // 写者互斥
    Semaphore read_sem // 写者等待所有读者完成
}

func new_rwmutex() RWMutex {
    RWMutex {
        readers:   0,
        writer:    0,
        write_mu:  new_mutex(),
        read_sem:  new_semaphore(0),
    }
}

impl RWMutex {
    // 读锁
    func rlock(mut self) () {
        // 若有写者在等，读者需等写者先完成（写优先）
        while __atomic_load(self.writer) == 1 {
            self.read_sem.wait()
        }
        __atomic_add(self.readers, 1)
    }

    func runlock(mut self) () {
        let prev = __atomic_add(self.readers, -1)
        if prev == 1 && __atomic_load(self.writer) == 1 {
            // 最后一个读者退出，通知等待的写者
            self.write_mu.sem.signal()
        }
    }

    // 写锁
    func wlock(mut self) () {
        self.write_mu.lock()
        __atomic_cas(self.writer, 0, 1)
        // 等待所有现有读者退出
        while __atomic_load(self.readers) > 0 {
            self.write_mu.sem.wait()
        }
    }

    func wunlock(mut self) () {
        __atomic_cas(self.writer, 1, 0)
        self.write_mu.unlock()
        // 唤醒所有等待的读者
        self.read_sem.signal()
    }
}

// ─── Once（只执行一次）───────────────────────────────────────
struct Once {
    int done    // 0 = 未执行，1 = 已执行
    Mutex mu
}

func new_once() Once {
    Once { done: 0, mu: new_mutex() }
}

impl Once {
    func do(mut self, func f) () {
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
}

func sema_unit_name() string { "src/runtime/sema" }
func sema_unit_ready() int   { 1 }
