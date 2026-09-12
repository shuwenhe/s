
package borrow_checker_guide


/**
借用检查器的核心职责：

1. 追踪每个变量的所有权
2. 验证引用的有效性
3. 检测冲突的借用
4. 确保引用生命周期有效

检查时机：编译时（静态分析）
*/


struct owner {
    *int resource
}

func ownership_rule1() {

    r := Owner{
        resource: box(42),
    }

}

func ownership_rule2() {

    r1 := Owner{
        resource: box(42),
    }
    r2 := r1
    


}

func ownership_rule3() {

    {
        r := Owner{
            resource: box(42),
        }

    }

}


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

struct data {
    *int value
}

func valid_shared_borrows() int {
    d := Data{value: box(100)}
    
    b1 := &d
    b2 := &d
    b3 := &d
    

    return *b1.value + *b2.value + *b3.value
}



func valid_sequential_mutable() int {
    d := Data{value: box(100)}
    
    {
        b1 := &mut d
        *b1.value = *b1.value + 10
    }
    
    {
        b2 := &mut d
        *b2.value = *b2.value + 20
    }
    
    return *d.value
}


/**
生命周期定义：借用的有效期

Key Concepts:
  1. Lifetime of Owner: 所有者的生命周期
  2. Lifetime of Borrow: 借用的生命周期
  3. Constraint: 借用不能比所有者活得更长
*/

struct container {
    *int data
}

func valid_lifetime() int {
    c := Container{data: box(50)}
    
    {

        ref := &c
        value := *ref.data

    }
    

    return *c.data
}


func borrow_from_param(c *Container) *int {

    return c.data
}


struct resource {
    *int ptr
}

func consume_resource(r Resource) int {
    return *r.ptr

}

func borrow_resource(r *Resource) int {
    return *r.ptr

}

func move_vs_borrow() int {
    r := Resource{ptr: box(100)}
    



    

    value := borrowResource(&r)

    
    return value
}


/**
编译器如何检测借用的作用域：

1. 借用创建：当使用 &x 或 &mut x 时
2. 借用使用：在引用被最后使用时
3. 借用结束：在NLL (Non-Lexical Lifetimes)之后
*/

struct box_int {
    *int ptr
}

func borrow_scope_example() int {
    b := box_int{ptr: box(50)}
    
    {

        ref := &b
        println(*ref.ptr)

    }
    
    {

        mut_ref := &b
        *mut_ref.ptr = 100
    }
    
    return *b.ptr
}


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






/**
伪代码 - 借用检查器的工作流程：

```
For each variable v:
  track_state(v, UNINITIALIZED)

For each statement:
  If assignment: v = e

    check_ownership(e)

    transfer_ownership(e, v)
    
  If borrow: ref = &v

    check_exclusive_mutable(v)

    create_shared_borrow(v)
    
  If mutable_borrow: ref = &mut v

    check_no_borrows(v)

    create_exclusive_borrow(v)
    
  If use: x = *ref

    check_lifetime_valid(ref)

    
  If scope_exit:

    for each v in scope:
      if not moved:
        drop(v)
```
*/


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

func state_transitions() int {
    r := Resource{ptr: box(10)}

    
    {
        ref := &r

        println(*ref.ptr)
    }

    
    r2 := r

    
    return *r2.ptr

}


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

func non_lexical_lifetime() int {
    r := Resource{ptr: box(50)}
    
    {
        ref := &r
        println(*ref.ptr)

    }
    
    {

        mut_ref := &r
        *mut_ref.ptr = 100
    }
    
    return *r.ptr
}




func return_ownership_example() Resource {
    r := Resource{ptr: box(100)}
    return r

}

func conditional_return(bool condition) Resource {
    r1 := Resource{ptr: box(1)}
    r2 := Resource{ptr: box(2)}
    
    if condition {
        return r1
    } else {
        return r2
    }
}


struct global_state {
    *int data
}



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

func best_practices() int {

    r := Resource{ptr: box(42)}
    

    value := useWithBorrow(&r)
    

    println(*r.ptr)
    
    return value
}

func use_with_borrow(r *Resource) int {
    return *r.ptr
}


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

