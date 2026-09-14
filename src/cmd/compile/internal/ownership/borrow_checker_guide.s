package borrow_checker_guide
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

func state_transitions() int {
    r := Resource{ptr: box(10)}
    {
        ref := &r
        println(*ref.ptr)
    }
    r2 := r
    return *r2.ptr
}

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

func best_practices() int {
    r := Resource{ptr: box(42)}
    value := useWithBorrow(&r)
    println(*r.ptr)
    return value
}

func use_with_borrow(r *Resource) int {
    return *r.ptr
}

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
