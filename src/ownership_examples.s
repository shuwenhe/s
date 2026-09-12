// ============================================================================
// Practical Ownership System Examples
// 实际应用示例：展示所有权系统的真实使用场景
// ============================================================================

package ownership_examples

// =============================================================================
// Example 1: Memory Allocator - 内存分配器
// 展示所有权追踪的内存管理
// =============================================================================

struct memory_block {
    addr *int
    size int
    allocated bool
}

func allocate_block(int size) MemoryBlock {
    return MemoryBlock{
        addr: box(size),
        size: size,
        allocated: true,
    }
}

func deallocate_block(block MemoryBlock) () {
    if block.allocated {

        _ = *block.addr
    }
}

func memory_example() int {

    block1 := allocateBlock(1024)
    block2 := allocateBlock(2048)
    

    block3 := block2
    

    total := block1.size + block3.size
    

    return total
}

// =============================================================================
// Example 2: String with Ownership - 有所有权的字符串
// 展示复杂数据结构的所有权
// =============================================================================

struct owned_string {
    data *int
    len int
    capacity int
}

func new_string(int capacity) OwnedString {
    return OwnedString{
        data: box(capacity),
        len: 0,
        capacity: capacity,
    }
}

func append_to_string(s *OwnedString, int value) () {
    if s.len < s.capacity {
        s.len = s.len + 1
    }
}

func string_example() int {
    s1 := newString(100)
    appendToString(&s1, 65)
    
    s2 := s1
    return s2.len

}

// =============================================================================
// Example 3: Vector/Dynamic Array - 动态数组
// 展示集合容器的所有权管理
// =============================================================================

struct vector {
    elements [100]*int
    len int
}

func new_vector() Vector {
    v := Vector{
        len: 0,
    }
    return v
}

func (v *Vector) push(int value) () {
    if v.len < 100 {
        v.elements[v.len] = box(value)
        v.len = v.len + 1
    }
}

func (v *Vector) get(int index) *int {
    if index < v.len {
        return v.elements[index]
    }
    return nil
}

func (v *Vector) len_value() int {
    return v.len
}

func vector_example() int {
    v := newVector()
    

    v.push(10)
    v.push(20)
    v.push(30)
    

    first := v.get(0)
    second := v.get(1)
    
    sum := *first + *second
    return sum

}

// =============================================================================
// Example 4: File Handle with RAII - 文件句柄
// 展示资源的获取和释放
// =============================================================================

struct file_handle {
    fd int
    open bool
}

func open_file(string path) FileHandle {
    return FileHandle{
        fd: 12345,
        open: true,
    }
}

func (f *FileHandle) read() int {
    if f.open {
        return f.fd * 10
    }
    return 0
}

func (f *FileHandle) write(int data) () {
    if f.open {
        _ = data
    }
}

func close_file(f FileHandle) () {
    if f.open {

        _ = f.fd
    }
}

func file_example() int {

    f := openFile("data.txt")
    

    content := f.read()
    

    return content
}

// =============================================================================
// Example 5: Linked List - 链表结构
// 展示递归数据结构的所有权
// =============================================================================

struct list_node {
    value int
    next *ListNode
}

func new_node(int value) ListNode {
    return ListNode{
        value: value,
        next: nil,
    }
}

func create_list(int head, int next_val) ListNode {
    node1 := newNode(head)
    node2 := newNode(next_val)

    return node1
}

func sum_list(node *ListNode) int {
    if node == nil {
        return 0
    }
    return node.value + sumList(node.next)
}

func list_example() int {
    head := createList(1, 2)
    return sumList(&head)
}

// =============================================================================
// Example 6: Reference Counting Alternative - 引用计数
// 展示如何在所有权系统中实现引用计数
// =============================================================================

struct ref_counted {
    data *int
    refCount *int
}

func new_ref_counted(int value) RefCounted {
    return RefCounted{
        data: box(value),
        refCount: box(1),
    }
}

func (rc *RefCounted) clone() RefCounted {
    *rc.refCount = *rc.refCount + 1
    return RefCounted{
        data: rc.data,
        refCount: rc.refCount,
    }
}

func ref_counted_example() int {
    rc1 := newRefCounted(100)
    rc2 := rc1.clone()
    

    val1 := *rc1.data
    val2 := *rc2.data
    
    return val1 + val2
}

// =============================================================================
// Example 7: State Machine - 状态机
// 展示所有权在状态转换中的作用
// =============================================================================

type ProcessState int
const (
    IDLE ProcessState = 0
    RUNNING ProcessState = 1
    STOPPED ProcessState = 2
)

struct process {
    state ProcessState
    data *int
}

func create_process() Process {
    return Process{
        state: IDLE,
        data: box(0),
    }
}

func (p *Process) start() () {
    p.state = RUNNING
    *p.data = 100
}

func (p *Process) stop() () {
    p.state = STOPPED
}

func process_example() int {
    proc := createProcess()
    proc.start()
    result := *proc.data
    proc.stop()
    return result
}

// =============================================================================
// Example 8: Owned Callback - 拥有的回调
// 展示捕获资源的回调函数
// =============================================================================

struct event_handler {
    callback func() int
    context *int
}

func create_event_handler(int contextData) EventHandler {
    context := box(contextData)
    
    return EventHandler{
        callback: func() int {
            return *context * 2
        },
        context: context,
    }
}

func trigger_event(handler *EventHandler) int {
    return handler.callback()
}

func callback_example() int {
    handler := createEventHandler(50)
    return triggerEvent(&handler)
}

// =============================================================================
// Example 9: Resource Pool - 资源池
// 展示容器管理多个资源
// =============================================================================

struct resource_pool {
    resources [10]*int
    count int
}

func new_pool() ResourcePool {
    return ResourcePool{
        count: 0,
    }
}

func (p *ResourcePool) acquire() *int {
    if p.count < 10 {
        p.resources[p.count] = box(p.count * 100)
        result := p.resources[p.count]
        p.count = p.count + 1
        return result
    }
    return nil
}

func (p *ResourcePool) size() int {
    return p.count
}

func pool_example() int {
    pool := newPool()
    
    r1 := pool.acquire()
    r2 := pool.acquire()
    r3 := pool.acquire()
    
    total := *r1 + *r2 + *r3
    return total

}

// =============================================================================
// Example 10: Copyable vs Moveable - Copy vs Move类型
// 展示两种类型的区别
// =============================================================================

// CopyableData: 可复制的数据（只包含值类型）
struct copyable_data {
    x int
    y int
}

// MoveableData: 需要move的数据（包含指针）
struct moveable_data {
    ptr *int
}

func copy_example() int {

    c1 := CopyableData{x: 10, y: 20}
    c2 := c1
    

    return c1.x + c2.y
}

func move_example() int {

    m1 := MoveableData{ptr: box(10)}
    m2 := m1
    

    value := *m2.ptr
    return value
}

// =============================================================================
// Example 11: Early Return Pattern - 提前返回模式
// 展示资源在不同返回路径中的所有权
// =============================================================================

struct validation_result {
    resource *int
    valid bool
}

func validate_and_allocate(int value) ValidationResult {
    if value < 0 {
        return ValidationResult{
            resource: nil,
            valid: false,
        }
    }
    
    resource := box(value * 2)
    return ValidationResult{
        resource: resource,
        valid: true,
    }
}

func early_return_example() int {
    result := validateAndAllocate(42)
    
    if !result.valid {
        return 0
    }
    
    return *result.resource
}

// =============================================================================
// Example 12: Complex Ownership Transfer - 复杂的所有权转移
// 展示多层所有权转移
// =============================================================================

struct container {
    item *int
}

struct wrapper {
    container Container
}

func deep_transfer() int {

    container := Container{
        item: box(100),
    }
    

    wrapper := Wrapper{
        container: container,
    }
    

    value := *wrapper.container.item
    return value

}

// =============================================================================
// Main: 运行所有示例
// =============================================================================

func main() int {

    println("=== Memory Allocator ===")
    println("Result:", memoryExample())
    

    println("=== Owned String ===")
    println("Result:", stringExample())
    

    println("=== Vector ===")
    println("Result:", vectorExample())
    

    println("=== File Handle ===")
    println("Result:", fileExample())
    

    println("=== Linked List ===")
    println("Result:", listExample())
    

    println("=== Reference Counting ===")
    println("Result:", refCountedExample())
    

    println("=== State Machine ===")
    println("Result:", processExample())
    

    println("=== Owned Callback ===")
    println("Result:", callbackExample())
    

    println("=== Resource Pool ===")
    println("Result:", poolExample())
    

    println("=== Copy vs Move ===")
    println("Copy result:", copyExample())
    println("Move result:", moveExample())
    

    println("=== Early Return ===")
    println("Result:", earlyReturnExample())
    

    println("=== Complex Transfer ===")
    println("Result:", deepTransfer())
    
    return 0
}

// =============================================================================
// 编译和运行
// =============================================================================
//
// cd /Users/feifei/shuwen/s
// ./bin/s_compiler src/ownership_examples.s -o /tmp/examples
// /tmp/examples
//
// =============================================================================
