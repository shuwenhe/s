// ============================================================================
// Borrow Checker Implementation Guide
// 借用检查器的详细实现和工作原理
// ============================================================================

package borrow_checker_guide

// =============================================================================
// Part 1: Borrow Checker Basics
// 借用检查器基础
// =============================================================================

/**
借用检查器的核心职责：

1. 追踪每个变量的所有权
2. 验证引用的有效性
3. 检测冲突的借用
4. 确保引用生命周期有效

检查时机：编译时（静态分析）
*/

// Rule Set 1: Ownership Rules
// 规则集1：所有权规则

type owner struct {
    resource *int
}

func ownership_rule1() {
    // Rule: 每个值都有一个所有者
    r := Owner{
        resource: box(42),
    }
    // r是resource的所有者
}

func ownership_rule2() {
    // Rule: 所有权可以转移
    r1 := Owner{
        resource: box(42),
    }
    r2 := r1  // r1的所有权转移给r2
    
    // r1现在无效（所有权已转移）
    // 使用r1会导致编译错误
}

func ownership_rule3() {
    // Rule: 当所有者离开作用域时，资源被销毁
    {
        r := Owner{
            resource: box(42),
        }
        // r拥有resource
    }
    // r离开作用域，resource自动销毁
}

// =============================================================================
// Part 2: Borrow Rules and Constraints
// 第2部分：借用规则和约束
// =============================================================================

/**
Borrow Checker的两条核心规则：

Rule 1: Shared Borrow (共享借用)
  - 可以有多个共享借用 (&T)
  - 所有者在借用期间不能被销毁
  - 所有者在借用期间不能被可变修改
  - 只读访问

Rule 2: Mutable Borrow (可变借用)
  - 同时只能有一个可变借用 (&mut T)
  - 所有者在借用期间不能被销毁
  - 所有者在借用期间不能被共享借用
  - 读写访问
*/

type data struct {
    value *int
}

// VALID: 多个共享借用
func valid_shared_borrows() int {
    d := Data{value: box(100)}
    
    b1 := &d
    b2 := &d
    b3 := &d
    
    // 所有借用都有效，可以共存
    return *b1.value + *b2.value + *b3.value
}

// ERROR CASE: 可变借用冲突
// func invalid_mutable_borrows() {
//     d := Data{value: box(100)}
//     
//     b1 := &mut d
//     b2 := &mut d  // ERROR: 两个可变借用不能共存
// }

// ERROR CASE: 共享和可变借用混合
// func invalid_mixed_borrows() {
//     d := Data{value: box(100)}
//     
//     s := &d
//     m := &mut d  // ERROR: 不能与共享借用混合
// }

// VALID: 顺序的可变借用
func valid_sequential_mutable() int {
    d := Data{value: box(100)}
    
    {
        b1 := &mut d
        *b1.value = *b1.value + 10
    }  // b1的借用在这里结束
    
    {
        b2 := &mut d
        *b2.value = *b2.value + 20
    }  // b2的借用在这里结束
    
    return *d.value
}

// =============================================================================
// Part 3: Lifetime Tracking
// 第3部分：生命周期追踪
// =============================================================================

/**
生命周期定义：借用的有效期

Key Concepts:
  1. Lifetime of Owner: 所有者的生命周期
  2. Lifetime of Borrow: 借用的生命周期
  3. Constraint: 借用不能比所有者活得更长
*/

type container struct {
    data *int
}

// VALID: 借用的生命周期短于所有者
func valid_lifetime() int {
    c := Container{data: box(50)}
    
    {
        // 借用开始
        ref := &c
        value := *ref.data
        // 借用结束
    }
    
    // c仍然有效
    return *c.data
}

// ERROR: 借用超过所有者的生命周期
// func invalid_lifetime() *int {
//     c := Container{data: box(50)}
//     ref := &c
//     return ref.data  // ERROR: ref指向c的数据
//                      //        但c的生命周期比返回值短
// }

// VALID: 返回值与参数的生命周期关系
func borrow_from_param(c *Container) *int {
    // 返回的引用生命周期受c的制约
    return c.data
}

// =============================================================================
// Part 4: Move vs Borrow
// 第4部分：Move vs Borrow
// =============================================================================

type resource struct {
    ptr *int
}

// MOVE: 转移所有权
func consume_resource(r Resource) int {
    return *r.ptr
    // r在这里销毁
}

// BORROW: 保留所有权
func borrow_resource(r *Resource) int {
    return *r.ptr
    // r仍然有效
}

// 对比示例
func move_vs_borrow() int {
    r := Resource{ptr: box(100)}
    
    // 选项1: 转移所有权（Move）
    // value1 := consumeResource(r)  // r的所有权转移
    // 下面无法使用r
    
    // 选项2: 借用（Borrow）- 推荐
    value := borrowResource(&r)
    // r仍然有效，可以继续使用
    
    return value
}

// =============================================================================
// Part 5: Borrow Scope Detection
// 第5部分：借用作用域检测
// =============================================================================

/**
编译器如何检测借用的作用域：

1. 借用创建：当使用 &x 或 &mut x 时
2. 借用使用：在引用被最后使用时
3. 借用结束：在NLL (Non-Lexical Lifetimes)之后
*/

type box_int struct {
    ptr *int
}

func borrow_scope_example() int {
    b := box_int{ptr: box(50)}
    
    {
        // 借用作用域开始
        ref := &b
        println(*ref.ptr)
        // 最后一次使用ref
    }  // 借用作用域结束
    
    {
        // 现在可以进行可变借用
        mut_ref := &b
        *mut_ref.ptr = 100
    }
    
    return *b.ptr
}

// =============================================================================
// Part 6: Conflict Detection
// 第6部分：冲突检测
// =============================================================================

/**
冲突类型：

1. Move + Use 冲突
   移动后使用变量

2. Mutable + Shared 冲突
   可变和共享借用混合

3. Multiple Mutable 冲突
   多个可变借用

4. Lifetime 冲突
   引用超出所有者生命周期
*/

// 冲突示例1: Move后使用
// func conflict_move_use() {
//     r := Resource{ptr: box(10)}
//     r2 := r  // Move
//     x := *r.ptr  // ERROR: r已moved
// }

// 冲突示例2: 可变借用冲突
// func conflict_mutable_borrow() {
//     r := Resource{ptr: box(10)}
//     m1 := &mut r
//     m2 := &mut r  // ERROR: 两个可变借用
// }

// 冲突示例3: 共享与可变混合
// func conflict_mixed_borrow() {
//     r := Resource{ptr: box(10)}
//     s := &r
//     m := &mut r  // ERROR: 混合借用
// }

// 冲突示例4: 生命周期冲突
// fn conflictLifetime() *int {
//     x := box(10)
//     return &x  // ERROR: &x在x销毁后无效
// }

// =============================================================================
// Part 7: Borrow Checker Algorithm
// 第7部分：借用检查器算法
// =============================================================================

/**
伪代码 - 借用检查器的工作流程：

```
For each variable v:
  track_state(v, UNINITIALIZED)

For each statement:
  If assignment: v = e
    // 检查e的所有权
    check_ownership(e)
    // 转移所有权给v
    transfer_ownership(e, v)
    
  If borrow: ref = &v
    // 检查v是否被独占借用
    check_exclusive_mutable(v)
    // 创建共享借用
    create_shared_borrow(v)
    
  If mutable_borrow: ref = &mut v
    // 检查v是否有任何借用
    check_no_borrows(v)
    // 创建可变借用
    create_exclusive_borrow(v)
    
  If use: x = *ref
    // 检查ref是否有效
    check_lifetime_valid(ref)
    // 使用ref
    
  If scope_exit:
    // 清理作用域内的所有变量
    for each v in scope:
      if not moved:
        drop(v)
```
*/

// =============================================================================
// Part 8: State Machine
// 第8部分：变量状态机
// =============================================================================

/**
变量可以处于以下状态之一：

State Diagram:
  
  ┌─────────────┐
  │Uninitialized│
  └──────┬──────┘
         │ (initialization)
         ▼
  ┌─────────────┐
  │   Owned     │◄────────────┐
  └──────┬──────┘             │
         │                    │ (borrow ends)
    ┌────┴────┐               │
    │ (borrow)│───────────────┤
    ├─────────┤               │
    ▼         ▼               │
  Shared    Mutable     ┌─────┴────┐
  Borrow    Borrow      │Borrowed  │
    │         │         └──────────┘
    └────┬────┘ (scope exit)
         │
         ▼
  ┌─────────────┐
  │  Destroyed  │
  └─────────────┘
*/

// State transitions example:
func state_transitions() int {
    r := Resource{ptr: box(10)}
    // State: r = Owned
    
    {
        ref := &r
        // State: r = Shared (borrowed)
        println(*ref.ptr)
    }
    // State: r = Owned (borrow ended)
    
    r2 := r
    // State: r = Moved, r2 = Owned
    
    return *r2.ptr
    // State: r2 = Destroyed
}

// =============================================================================
// Part 9: NLL (Non-Lexical Lifetimes)
// 第9部分：非词法生命周期
// =============================================================================

/**
NLL是一种更精确的生命周期推断方式：

词法（Lexical）生命周期：
  - 基于作用域块 {}
  - 从创建到块结束有效

非词法（Non-Lexical）生命周期：
  - 基于最后使用位置
  - 从创建到最后使用后有效
  - 更精确，更少的错误报告
*/

// 使用NLL的示例
func non_lexical_lifetime() int {
    r := Resource{ptr: box(50)}
    
    {
        ref := &r
        println(*ref.ptr)
        // ref的最后使用在这里
    }  // ref的借用在这里结束（不是块结束）
    
    {
        // 可以立即进行可变借用
        mut_ref := &r
        *mut_ref.ptr = 100
    }
    
    return *r.ptr
}

// 比较：词法vs非词法
// 词法生命周期（严格）：
// fn lexical() {
//     let mut r = Resource { ... };
//     {
//         let ref = &r;
//         println!("{}", *ref);
//     }  // ref的生命周期到这里结束
//     r = new_resource();  // OK
// }

// 非词法生命周期（灵活）：
// fn non_lexical() {
//     let mut r = Resource { ... };
//     {
//         let ref = &r;
//         println!("{}", *ref);
//         // ref的生命周期在这里结束（最后使用）
//     }
//     r = new_resource();  // OK - 相同的代码更早允许
// }

// =============================================================================
// Part 10: Special Cases
// 第10部分：特殊情况
// =============================================================================

// 特殊情况1: 返回值的所有权
func return_ownership_example() Resource {
    r := Resource{ptr: box(100)}
    return r  // OK - 所有权转移给调用者
    // r的销毁责任转移
}

// 特殊情况2: 条件返回
func conditional_return(bool condition) Resource {
    r1 := Resource{ptr: box(1)}
    r2 := Resource{ptr: box(2)}
    
    if condition {
        return r1  // r1转移给调用者，r2销毁
    } else {
        return r2  // r2转移给调用者，r1销毁
    }
}

// 特殊情况3: 自引用（有限支持）
// type node struct {
//     value int
//     next *Node  // 需要谨慎使用
// }

// 特殊情况4: 全局状态
type global_state struct {
    data *int
}

// 全局所有权管理需要特殊处理

// =============================================================================
// Part 11: Error Messages from Borrow Checker
// 第11部分：借用检查器的错误消息
// =============================================================================

/**
常见的借用检查器错误消息：

Error 1: Use of moved value
  cannot use value after move
  值在移动后无法使用

Error 2: Mutable borrow conflicts
  cannot have two mutable references
  不能有两个可变引用

Error 3: Mixed borrow conflict
  cannot borrow as mutable when already borrowed as immutable
  当已有不可变借用时不能进行可变借用

Error 4: Lifetime mismatch
  lifetime mismatch
  生命周期不匹配

Error 5: Dangling reference
  this function's return type contains a borrowed value with an
  explicit lifetime that does not appear in any of the function arguments
  返回的引用没有有效的所有者
*/

// =============================================================================
// Part 12: Best Practices
// 第12部分：最佳实践
// =============================================================================

/**
1. 倾向于借用而非转移所有权
   - 使用 &T 和 &mut T 保留所有权
   - 只在必要时转移所有权

2. 在作用域中明确借用
   - 使用块来限制借用生命周期
   - 使代码意图清晰

3. 避免可变状态
   - 优先使用不可变的设计
   - 只在必要时使用可变引用

4. 使用返回值而非输出参数
   - Rust风格：返回所有权
   - 避免复杂的生命周期

5. 小心自引用
   - 避免数据结构自引用
   - 使用索引或其他间接方式

6. 理解所有权转移的成本
   - 某些类型的移动很便宜（指针）
   - 某些类型的移动很昂贵（大结构）
*/

// 示例：最佳实践
func best_practices() int {
    // 1. 使用借用
    r := Resource{ptr: box(42)}
    
    // 2. 传递引用而不是转移所有权
    value := useWithBorrow(&r)
    
    // 3. r仍然有效
    println(*r.ptr)
    
    return value
}

func use_with_borrow(r *Resource) int {
    return *r.ptr
}

// =============================================================================
// Part 13: Integration with Ownership System
// 第13部分：与所有权系统的集成
// =============================================================================

/**
三者的关系：

Ownership (所有权)
  ├─→ 定义谁拥有资源
  │
  ├─→ Borrow Checker (借用检查)
  │   ├─→ 验证借用的有效性
  │   ├─→ 防止冲突访问
  │   └─→ 追踪引用生命周期
  │
  └─→ Drop (自动析构)
      ├─→ 释放资源
      ├─→ 调用清理代码
      └─→ 防止泄漏

流程：编译时检查 → 运行时执行 → 自动清理
*/

// =============================================================================
// Compilation and Testing
// =============================================================================

func main() int {
    println("=== Ownership Rules ===") ownership_rule1()
    
    println("=== Valid Shared Borrows ===")
    println(validSharedBorrows())
    
    println("=== Valid Sequential Mutable ===")
    println(validSequentialMutable())
    
    println("=== Valid Lifetime ===")
    println(validLifetime())
    
    println("=== Move vs Borrow ===")
    println(moveVsBorrow())
    
    println("=== Borrow Scope ===")
    println(borrowScopeExample())
    
    println("=== State Transitions ===")
    println(stateTransitions())
    
    println("=== Non-Lexical Lifetime ===")
    println(nonLexicalLifetime())
    
    println("=== Conditional Return ===")
    cr := conditionalReturn(true)
    println(*cr.ptr)
    
    println("=== Best Practices ===")
    println(bestPractices())
    
    return 0
}

// =============================================================================
// 参考资源
// =============================================================================
//
// - 所有权系统实现: /Users/feifei/shuwen/s/src/ownership_system.s
// - 所有权系统指南: /Users/feifei/shuwen/s/doc/OWNERSHIP_SYSTEM.md
// - Rust Borrow Checker 文档:
//   https://doc.rust-lang.org/book/ch04-02-references-and-borrowing.html
//
// =============================================================================
