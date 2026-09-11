// ============================================================================
// Practical Ownership System Examples
// 实际应用示例：展示所有权系统的真实使用场景
// ============================================================================

package ownership_examples

// =============================================================================
// Example 1: Memory Allocator - 内存分配器
// 展示所有权追踪的内存管理
// =============================================================================

type MemoryBlock struct {
    addr *int
    size int
    allocated bool
}

func allocateBlock(size int) MemoryBlock {
    return MemoryBlock{
        addr: box(size),
        size: size,
        allocated: true,
    }
}

func deallocateBlock(block MemoryBlock) () {
    if block.allocated {
        // 内存被释放，block不再有效
        _ = *block.addr
    }
}

func memoryExample() int {
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

type OwnedString struct {
    data *int  // 指向字符数据
    len int
    capacity int
}

func newString(capacity int) OwnedString {
    return OwnedString{
        data: box(capacity),
        len: 0,
        capacity: capacity,
    }
}

func appendToString(s *OwnedString, value int) () {
    if s.len < s.capacity {
        s.len = s.len + 1
    }
}

func stringExample() int {
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

type Vector struct {
    elements [100]*int  // 固定大小数组
    len int
}

func newVector() Vector {
    v := Vector{
        len: 0,
    }
    return v
}

func (v *Vector) push(value int) () {
    if v.len < 100 {
        v.elements[v.len] = box(value)
        v.len = v.len + 1
    }
}

func (v *Vector) get(index int) *int {
    if index < v.len {
        return v.elements[index]
    }
    return nil
}

func (v *Vector) len_value() int {
    return v.len
}

func vectorExample() int {
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

type FileHandle struct {
    fd int
    open bool
}

func openFile(path string) FileHandle {
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

func (f *FileHandle) write(data int) () {
    if f.open {
        _ = data  // 写入
    }
}

func closeFile(f FileHandle) () {
    if f.open {
        // 关闭文件
        _ = f.fd
    }
}

func fileExample() int {
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

type ListNode struct {
    value int
    next *ListNode
}

func newNode(value int) ListNode {
    return ListNode{
        value: value,
        next: nil,
    }
}

func createList(head int, next_val int) ListNode {
    node1 := newNode(head)
    node2 := newNode(next_val)
    // 模拟链表构建（实际使用会更复杂）
    return node1
}

func sumList(node *ListNode) int {
    if node == nil {
        return 0
    }
    return node.value + sumList(node.next)
}

func listExample() int {
    head := createList(1, 2)
    return sumList(&head)
}

// =============================================================================
// Example 6: Reference Counting Alternative - 引用计数
// 展示如何在所有权系统中实现引用计数
// =============================================================================

type RefCounted struct {
    data *int
    refCount *int
}

func newRefCounted(value int) RefCounted {
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

func refCountedExample() int {
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

type Process struct {
    state ProcessState
    data *int
}

func createProcess() Process {
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

func processExample() int {
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

type EventHandler struct {
    callback func() int
    context *int
}

func createEventHandler(contextData int) EventHandler {
    context := box(contextData)
    
    return EventHandler{
        callback: func() int {
            return *context * 2
        },
        context: context,
    }
}

func triggerEvent(handler *EventHandler) int {
    return handler.callback()
}

func callbackExample() int {
    handler := createEventHandler(50)
    return triggerEvent(&handler)
}

// =============================================================================
// Example 9: Resource Pool - 资源池
// 展示容器管理多个资源
// =============================================================================

type ResourcePool struct {
    resources [10]*int
    count int
}

func newPool() ResourcePool {
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

func poolExample() int {
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
type CopyableData struct {
    x int
    y int
}

// MoveableData: 需要move的数据（包含指针）
type MoveableData struct {
    ptr *int
}

func copyExample() int {
    // Copy类型：值被复制
    c1 := CopyableData{x: 10, y: 20}
    c2 := c1  // c1的值被复制给c2
    
    // c1和c2都有效
    return c1.x + c2.y
}

func moveExample() int {
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

type ValidationResult struct {
    resource *int
    valid bool
}

func validateAndAllocate(value int) ValidationResult {
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

func earlyReturnExample() int {
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

type Container struct {
    item *int
}

type Wrapper struct {
    container Container
}

func deepTransfer() int {
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
