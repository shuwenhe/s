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
        // 内存被释放，block不再有效
        _ = *block.addr
    }
}

func memory_example() int {
    // 分配内存块
    block1 := allocateBlock(1024)
    block2 := allocateBlock(2048)
    
    // 在某个点转移所有权
    block3 := block2  // block2的所有权转移给block3
    
    // 使用block
    total := block1.size + block3.size
    
    // 块在作用域结束时自动销毁
    return total
}

// =============================================================================
// Example 2: String with Ownership - 有所有权的字符串
// 展示复杂数据结构的所有权
// =============================================================================

struct owned_string {
    data *int  // 指向字符数据
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
    s1 := newString(100)  // s1拥有字符串数据
    appendToString(&s1, 65)
    
    s2 := s1  // s1的所有权转移给s2，s1不再有效
    return s2.len
    // s2在这里销毁，所有数据被释放
}

// =============================================================================
// Example 3: Vector/Dynamic Array - 动态数组
// 展示集合容器的所有权管理
// =============================================================================

struct vector {
    elements [100]*int  // 固定大小数组
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
    
    // 向向量添加元素
    v.push(10)
    v.push(20)
    v.push(30)
    
    // 访问元素（借用）
    first := v.get(0)
    second := v.get(1)
    
    sum := *first + *second
    return sum
    // v离开作用域时，所有elements被自动清理
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
        fd: 12345,  // 模拟文件描述符
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
        _ = data  // 写入
    }
}

func close_file(f FileHandle) () {
    if f.open {
        // 关闭文件
        _ = f.fd
    }
}

func file_example() int {
    // 打开文件
    f := openFile("data.txt")
    
    // 使用文件
    content := f.read()
    
    // 文件自动关闭（或显式调用closeFile）
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
    // 模拟链表构建（实际使用会更复杂）
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
    
    // rc1和rc2共享数据，但两个都拥有
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
    // pool销毁时所有资源被自动清理
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
    // Copy类型：值被复制
    c1 := CopyableData{x: 10, y: 20}
    c2 := c1  // c1的值被复制给c2
    
    // c1和c2都有效
    return c1.x + c2.y
}

func move_example() int {
    // Moveable类型：所有权被转移
    m1 := MoveableData{ptr: box(10)}
    m2 := m1  // m1的所有权转移给m2
    
    // 这里只能使用m2
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
    // 第1层：创建资源
    container := Container{
        item: box(100),
    }
    
    // 第2层：包装
    wrapper := Wrapper{
        container: container,
    }
    
    // 第3层：提取
    value := *wrapper.container.item
    return value
    // 所有权在各层之间转移，最终在这里全部销毁
}

// =============================================================================
// Main: 运行所有示例
// =============================================================================

func main() int {
    // 示例1
    println("=== Memory Allocator ===")
    println("Result:", memoryExample())
    
    // 示例2
    println("=== Owned String ===")
    println("Result:", stringExample())
    
    // 示例3
    println("=== Vector ===")
    println("Result:", vectorExample())
    
    // 示例4
    println("=== File Handle ===")
    println("Result:", fileExample())
    
    // 示例5
    println("=== Linked List ===")
    println("Result:", listExample())
    
    // 示例6
    println("=== Reference Counting ===")
    println("Result:", refCountedExample())
    
    // 示例7
    println("=== State Machine ===")
    println("Result:", processExample())
    
    // 示例8
    println("=== Owned Callback ===")
    println("Result:", callbackExample())
    
    // 示例9
    println("=== Resource Pool ===")
    println("Result:", poolExample())
    
    // 示例10
    println("=== Copy vs Move ===")
    println("Copy result:", copyExample())
    println("Move result:", moveExample())
    
    // 示例11
    println("=== Early Return ===")
    println("Result:", earlyReturnExample())
    
    // 示例12
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
