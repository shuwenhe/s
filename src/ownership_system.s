// ============================================================================
// Ownership System in S Language
// A memory and resource management system without GC
// 所有权系统：ownership / borrow / drop / lifetime
// ============================================================================

package ownership_system

// =============================================================================
// Part 1: Core Ownership Model
// =============================================================================

// Resource: 一个基础资源结构，展示所有权和Drop
type Resource struct {
    ptr *int
    id int
}

// Constructor: 创建一个新资源
func newResource(id int) Resource {
    resource := Resource{
        ptr: box(id * 10),
        id: id,
    }
    return resource
}

// Drop trait equivalent: 资源的清理逻辑
// 在S中，当Resource离开作用域时，自动调用析构函数
func (r Resource) dropMe() () {
    // 释放内部资源
    if r.ptr != nil {
        // 在S中，box自动管理内存，当ptr离开作用域时自动释放
        _ = *r.ptr
    }
}

// =============================================================================
// Part 2: Ownership Transfer (Move Semantics)
// =============================================================================

// moveOwnership: 演示所有权转移
// 当resource作为参数传入时，所有权转移给函数
func moveOwnership(resource Resource) int {
    value := *resource.ptr
    // resource的所有权现在在这个函数中
    // 函数结束时，resource被自动销毁
    return value
}

// returnOwnership: 所有权从函数返回给调用者
func returnOwnership() Resource {
    r := newResource(42)
    // 所有权从这个函数转移给调用者
    return r
}

// swapOwnership: 两个资源交换所有权
func swapOwnership(r1 Resource, r2 Resource) (Resource, Resource) {
    return r2, r1
}

// =============================================================================
// Part 3: Borrowing (Shared and Mutable References)
// =============================================================================

// borrowShared: 共享借用 - 只读访问，不转移所有权
// 多个共享借用可以同时存在
func borrowShared(r *Resource) int {
    // 可以读取r的内容，但不能修改
    if r.ptr != nil {
        return *r.ptr
    }
    return 0
}

// borrowMutable: 可变借用 - 读写访问，但同一时间只能有一个
// 可变借用会独占资源
func borrowMutable(r *Resource) () {
    if r.ptr != nil {
        *r.ptr = *r.ptr + 100
    }
}

// borrowMultipleShared: 展示多个共享借用的安全性
func borrowMultipleShared(r *Resource) int {
    first := borrowShared(r)
    second := borrowShared(r)
    third := borrowShared(r)
    return first + second + third
}

// =============================================================================
// Part 4: Scope-based Cleanup (Automatic Drop)
// =============================================================================

// demonstrateScope: 展示作用域退出时的自动清理
func demonstrateScope() int {
    total := 0
    
    {
        // 在这个块中创建资源
        r1 := newResource(1)
        total = total + *r1.ptr
        // r1在这里离开作用域，自动被销毁
    }
    // r1已经被销毁，无法访问
    
    {
        r2 := newResource(2)
        {
            r3 := newResource(3)
            total = total + *r3.ptr
            // r3在这里离开作用域
        }
        total = total + *r2.ptr
        // r2在这里离开作用域
    }
    
    return total
}

// =============================================================================
// Part 5: Lifetime Checking with Scopes
// =============================================================================

// LifetimeTracker: 用于追踪引用的生命周期
type LifetimeTracker struct {
    ref *int
    createdAt int
}

// borrowWithLifetime: 演示生命周期约束
// 返回的引用的生命周期不能长于所有者
func borrowWithLifetime(r *Resource) *int {
    // 返回的引用生命周期受限于r的生命周期
    return r.ptr
}

// demonstrateLifetimeInvalid: 展示无效的生命周期（注释掉会编译错误）
// func demonstrateLifetimeInvalid() *int {
//     r := newResource(99)
//     ptr := borrowWithLifetime(&r)
//     return ptr  // ERROR: ptr引用的资源已被销毁
// }

// demonstrateLifetimeValid: 展示有效的生命周期
func demonstrateLifetimeValid() int {
    r := newResource(99)
    ptr := borrowWithLifetime(&r)
    value := *ptr
    // r的生命周期在这里结束，ptr也变得无效
    return value
}

// =============================================================================
// Part 6: Box - Owned Heap Allocation
// =============================================================================

// BoxedResource: 展示堆分配的所有权
type BoxedResource struct {
    data *int
}

// createBoxedResource: 在堆上创建资源
func createBoxedResource(value int) BoxedResource {
    return BoxedResource{
        data: box(value),
    }
}

// consumeBoxed: 消费boxed资源，取得所有权
func consumeBoxed(br BoxedResource) int {
    return *br.data
    // br在这里超出作用域，data会被自动释放
}

// =============================================================================
// Part 7: Move vs Copy Semantics
// =============================================================================

// MoveType: 需要move的类型（包含堆分配或指针）
type MoveType struct {
    ptr *int
}

// CopyType: 可以copy的类型（只包含值类型）
type CopyType struct {
    value int
}

// demonstrateMoveSemantics: 展示move语义
func demonstrateMoveSemantics() int {
    // Move: 所有权转移
    m1 := MoveType{ ptr: box(10) }
    m2 := m1  // m1的所有权转移给m2，m1不再有效
    
    // m1现在无法使用
    value := *m2.ptr
    return value
}

// demonstrateCopySemantics: 展示copy语义
func demonstrateCopySemantics() int {
    // Copy: 值被复制
    c1 := CopyType{ value: 10 }
    c2 := c1  // c1的值被复制给c2，c1仍然有效
    
    // c1和c2都有效
    return c1.value + c2.value
}

// =============================================================================
// Part 8: Drop Flag Tracking
// =============================================================================

// DropFlaggedResource: 带有drop flag的资源（用于追踪是否已销毁）
type DropFlaggedResource struct {
    ptr *int
    dropped bool  // 模拟drop flag
}

// newDropFlaggedResource: 创建一个新的drop-flagged资源
func newDropFlaggedResource(value int) DropFlaggedResource {
    return DropFlaggedResource{
        ptr: box(value),
        dropped: false,
    }
}

// getValue: 安全地获取值（检查drop flag）
func (r *DropFlaggedResource) getValue() (int, bool) {
    if r.dropped {
        return 0, false  // 错误：资源已被销毁
    }
    return *r.ptr, true
}

// dropIt: 显式销毁资源
func (r *DropFlaggedResource) dropIt() () {
    if !r.dropped {
        // 清理资源
        _ = *r.ptr
        r.dropped = true
    }
}

// =============================================================================
// Part 9: RAII Pattern (Resource Acquisition Is Initialization)
// =============================================================================

// RAIIResource: 展示RAII模式
type RAIIResource struct {
    id int
    handle *int
}

// acquireResource: 获取资源
func acquireResource(id int) RAIIResource {
    return RAIIResource{
        id: id,
        handle: box(id * 1000),
    }
}

// useResource: 使用资源
func (r *RAIIResource) useResource() int {
    if r.handle != nil {
        return *r.handle
    }
    return 0
}

// releaseResource: 在资源对象销毁时自动调用
func (r RAIIResource) releaseResource() () {
    // 在生命周期结束时自动清理
    if r.handle != nil {
        _ = *r.handle
    }
}

// =============================================================================
// Part 10: Complex Ownership Scenarios
// =============================================================================

// Container: 演示容器拥有的资源
type Container struct {
    resources []*int
    count int
}

// addToContainer: 添加资源到容器（转移所有权）
func (c *Container) addToContainer(value int) () {
    // 容器获取资源的所有权
    ptr := box(value)
    c.resources[c.count] = ptr
    c.count = c.count + 1
}

// getFromContainer: 从容器中获取引用（共享借用）
func (c *Container) getFromContainer(index int) *int {
    if index < c.count {
        return c.resources[index]
    }
    return nil
}

// =============================================================================
// Part 11: Ownership in Control Flow
// =============================================================================

// ownershipWithReturn: 所有权随return语句转移
func ownershipWithReturn(condition bool) Resource {
    r1 := newResource(1)
    r2 := newResource(2)
    
    if condition {
        return r1  // r1的所有权返回，r2自动销毁
    }
    
    return r2  // r2的所有权返回，r1自动销毁
}

// ownershipWithLoop: 展示循环中的所有权
func ownershipWithLoop(n int) int {
    total := 0
    i := 0
    
    for i < n {
        r := newResource(i)
        total = total + *r.ptr
        i = i + 1
        // r在每次循环迭代结束时销毁
    }
    
    return total
}

// =============================================================================
// Part 12: Main Demonstration
// =============================================================================

func main() int {
    // 演示1: 基础所有权
    println("=== Ownership Transfer ===")
    r := newResource(5)
    value := moveOwnership(r)
    println("Moved value: ", value)
    
    // 演示2: 所有权返回
    println("\n=== Return Ownership ===")
    r2 := returnOwnership()
    println("Returned value: ", *r2.ptr)
    
    // 演示3: 借用（共享）
    println("\n=== Shared Borrow ===")
    r3 := newResource(15)
    sum := borrowMultipleShared(&r3)
    println("Sum of multiple borrows: ", sum)
    
    // 演示4: 作用域清理
    println("\n=== Scope-based Cleanup ===")
    scopeTotal := demonstrateScope()
    println("Scope cleanup total: ", scopeTotal)
    
    // 演示5: 可变借用
    println("\n=== Mutable Borrow ===")
    r4 := newResource(20)
    borrowMutable(&r4)
    println("After mutable borrow: ", *r4.ptr)
    
    // 演示6: 生命周期有效性
    println("\n=== Lifetime Validity ===")
    ltVal := demonstrateLifetimeValid()
    println("Lifetime valid value: ", ltVal)
    
    // 演示7: Boxed资源
    println("\n=== Boxed Resource ===")
    br := createBoxedResource(88)
    boxVal := consumeBoxed(br)
    println("Boxed value: ", boxVal)
    
    // 演示8: Move vs Copy
    println("\n=== Move Semantics ===")
    moveVal := demonstrateMoveSemantics()
    println("After move: ", moveVal)
    
    println("\n=== Copy Semantics ===")
    copyVal := demonstrateCopySemantics()
    println("Copy result: ", copyVal)
    
    // 演示9: 循环中的所有权
    println("\n=== Loop Ownership ===")
    loopTotal := ownershipWithLoop(5)
    println("Loop total: ", loopTotal)
    
    // 演示10: 条件中的所有权
    println("\n=== Conditional Ownership ===")
    cr := ownershipWithReturn(true)
    println("Conditional return: ", *cr.ptr)
    
    return 0
}

// =============================================================================
// Compilation Instructions
// =============================================================================
//
// Build and test this ownership system:
// 
//   cd /Users/feifei/shuwen/s
//   make compiler
//   ./bin/s_compiler ownership_system.s -o /tmp/ownership
//   /tmp/ownership
//
// This will generate C code with explicit resource management, no GC needed.
//
// Key Features Demonstrated:
// 1. Ownership Transfer: Resources moved when passed to functions
// 2. Borrow Checker: Shared and mutable borrows controlled
// 3. Automatic Drop: Cleanup happens at scope exit
// 4. Lifetime Rules: Borrowed references can't outlive owners
// 5. RAII Pattern: Resource lifecycle tied to object lifetime
// 6. Move Semantics: Ownership-based resource transfer
// 7. Drop Flags: Tracking whether resources have been destroyed
// 8. Control Flow: Ownership respected in if/return/loops
//
// =============================================================================
