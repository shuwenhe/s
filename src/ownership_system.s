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
struct resource {
    ptr *int
    id int
}

// Constructor: 创建一个新资源
func new_resource(int id) Resource {
    resource := Resource{
        ptr: box(id * 10),
        id: id,
    }
    return resource
}

// Drop trait equivalent: 资源的清理逻辑
// 在S中，当Resource离开作用域时，自动调用析构函数
func (r Resource) drop_me() () {

    if r.ptr != nil {

        _ = *r.ptr
    }
}

// =============================================================================
// Part 2: Ownership Transfer (Move Semantics)
// =============================================================================

// moveOwnership: 演示所有权转移
// 当resource作为参数传入时，所有权转移给函数
func move_ownership(resource Resource) int {
    value := *resource.ptr


    return value
}

// returnOwnership: 所有权从函数返回给调用者
func return_ownership() Resource {
    r := newResource(42)

    return r
}

// swapOwnership: 两个资源交换所有权
func swap_ownership(r1 Resource, r2 Resource) (Resource, Resource) {
    return r2, r1
}

// =============================================================================
// Part 3: Borrowing (Shared and Mutable References)
// =============================================================================

// borrowShared: 共享借用 - 只读访问，不转移所有权
// 多个共享借用可以同时存在
func borrow_shared(r *Resource) int {

    if r.ptr != nil {
        return *r.ptr
    }
    return 0
}

// borrowMutable: 可变借用 - 读写访问，但同一时间只能有一个
// 可变借用会独占资源
func borrow_mutable(r *Resource) () {
    if r.ptr != nil {
        *r.ptr = *r.ptr + 100
    }
}

// borrowMultipleShared: 展示多个共享借用的安全性
func borrow_multiple_shared(r *Resource) int {
    first := borrowShared(r)
    second := borrowShared(r)
    third := borrowShared(r)
    return first + second + third
}

// =============================================================================
// Part 4: Scope-based Cleanup (Automatic Drop)
// =============================================================================

// demonstrateScope: 展示作用域退出时的自动清理
func demonstrate_scope() int {
    total := 0
    
    {

        r1 := newResource(1)
        total = total + *r1.ptr

    }

    
    {
        r2 := newResource(2)
        {
            r3 := newResource(3)
            total = total + *r3.ptr

        }
        total = total + *r2.ptr

    }
    
    return total
}

// =============================================================================
// Part 5: Lifetime Checking with Scopes
// =============================================================================

// LifetimeTracker: 用于追踪引用的生命周期
struct lifetime_tracker {
    ref *int
    createdAt int
}

// borrowWithLifetime: 演示生命周期约束
// 返回的引用的生命周期不能长于所有者
func borrow_with_lifetime(r *Resource) *int {

    return r.ptr
}

// demonstrateLifetimeInvalid: 展示无效的生命周期（注释掉会编译错误）
// func demonstrate_lifetime_invalid() *int {
//     r := newResource(99)
//     ptr := borrowWithLifetime(&r)
//     return ptr
// }

// demonstrateLifetimeValid: 展示有效的生命周期
func demonstrate_lifetime_valid() int {
    r := newResource(99)
    ptr := borrowWithLifetime(&r)
    value := *ptr

    return value
}

// =============================================================================
// Part 6: Box - Owned Heap Allocation
// =============================================================================

// BoxedResource: 展示堆分配的所有权
struct boxed_resource {
    data *int
}

// createBoxedResource: 在堆上创建资源
func create_boxed_resource(int value) BoxedResource {
    return BoxedResource{
        data: box(value),
    }
}

// consumeBoxed: 消费boxed资源，取得所有权
func consume_boxed(br BoxedResource) int {
    return *br.data

}

// =============================================================================
// Part 7: Move vs Copy Semantics
// =============================================================================

// MoveType: 需要move的类型（包含堆分配或指针）
struct move_type {
    ptr *int
}

// CopyType: 可以copy的类型（只包含值类型）
struct copy_type {
    value int
}

// demonstrateMoveSemantics: 展示move语义
func demonstrate_move_semantics() int {

    m1 := MoveType{ ptr: box(10) }
    m2 := m1
    

    value := *m2.ptr
    return value
}

// demonstrateCopySemantics: 展示copy语义
func demonstrate_copy_semantics() int {

    c1 := CopyType{ value: 10 }
    c2 := c1
    

    return c1.value + c2.value
}

// =============================================================================
// Part 8: Drop Flag Tracking
// =============================================================================

// DropFlaggedResource: 带有drop flag的资源（用于追踪是否已销毁）
struct drop_flagged_resource {
    ptr *int
    dropped bool
}

// newDropFlaggedResource: 创建一个新的drop-flagged资源
func new_drop_flagged_resource(int value) DropFlaggedResource {
    return DropFlaggedResource{
        ptr: box(value),
        dropped: false,
    }
}

// getValue: 安全地获取值（检查drop flag）
func (r *DropFlaggedResource) get_value() (int, bool) {
    if r.dropped {
        return 0, false
    }
    return *r.ptr, true
}

// dropIt: 显式销毁资源
func (r *DropFlaggedResource) drop_it() () {
    if !r.dropped {

        _ = *r.ptr
        r.dropped = true
    }
}

// =============================================================================
// Part 9: RAII Pattern (Resource Acquisition Is Initialization)
// =============================================================================

// RAIIResource: 展示RAII模式
struct raii_resource {
    id int
    handle *int
}

// acquireResource: 获取资源
func acquire_resource(int id) RAIIResource {
    return RAIIResource{
        id: id,
        handle: box(id * 1000),
    }
}

// useResource: 使用资源
func (r *RAIIResource) use_resource() int {
    if r.handle != nil {
        return *r.handle
    }
    return 0
}

// releaseResource: 在资源对象销毁时自动调用
func (r RAIIResource) release_resource() () {

    if r.handle != nil {
        _ = *r.handle
    }
}

// =============================================================================
// Part 10: Complex Ownership Scenarios
// =============================================================================

// Container: 演示容器拥有的资源
struct container {
    resources []*int
    count int
}

// addToContainer: 添加资源到容器（转移所有权）
func (c *Container) add_to_container(int value) () {

    ptr := box(value)
    c.resources[c.count] = ptr
    c.count = c.count + 1
}

// getFromContainer: 从容器中获取引用（共享借用）
func (c *Container) get_from_container(int index) *int {
    if index < c.count {
        return c.resources[index]
    }
    return nil
}

// =============================================================================
// Part 11: Ownership in Control Flow
// =============================================================================

// ownershipWithReturn: 所有权随return语句转移
func ownership_with_return(bool condition) Resource {
    r1 := newResource(1)
    r2 := newResource(2)
    
    if condition {
        return r1
    }
    
    return r2
}

// ownershipWithLoop: 展示循环中的所有权
func ownership_with_loop(int n) int {
    total := 0
    i := 0
    
    for i < n {
        r := newResource(i)
        total = total + *r.ptr
        i = i + 1

    }
    
    return total
}

// =============================================================================
// Part 12: Main Demonstration
// =============================================================================

func main() int {

    println("=== Ownership Transfer ===")
    r := newResource(5)
    value := moveOwnership(r)
    println("Moved value: ", value)
    

    println("\n=== Return Ownership ===")
    r2 := returnOwnership()
    println("Returned value: ", *r2.ptr)
    

    println("\n=== Shared Borrow ===")
    r3 := newResource(15)
    sum := borrowMultipleShared(&r3)
    println("Sum of multiple borrows: ", sum)
    

    println("\n=== Scope-based Cleanup ===")
    scope_total := demonstrateScope()
    println("Scope cleanup total: ", scope_total)
    

    println("\n=== Mutable Borrow ===")
    r4 := newResource(20) borrow_mutable(&r4)
    println("After mutable borrow: ", *r4.ptr)
    

    println("\n=== Lifetime Validity ===")
    lt_val := demonstrateLifetimeValid()
    println("Lifetime valid value: ", lt_val)
    

    println("\n=== Boxed Resource ===")
    br := createBoxedResource(88)
    box_val := consumeBoxed(br)
    println("Boxed value: ", box_val)
    

    println("\n=== Move Semantics ===")
    move_val := demonstrateMoveSemantics()
    println("After move: ", move_val)
    
    println("\n=== Copy Semantics ===")
    copy_val := demonstrateCopySemantics()
    println("Copy result: ", copy_val)
    

    println("\n=== Loop Ownership ===")
    loop_total := ownershipWithLoop(5)
    println("Loop total: ", loop_total)
    

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
