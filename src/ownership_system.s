
package ownership_system


struct resource {
    ptr *int
    id int
}

func new_resource(int id) Resource {
    resource := Resource{
        ptr: box(id * 10),
        id: id,
    }
    return resource
}

func (r Resource) drop_me() () {

    if r.ptr != nil {

        _ = *r.ptr
    }
}


func move_ownership(resource Resource) int {
    value := *resource.ptr


    return value
}

func return_ownership() Resource {
    r := newResource(42)

    return r
}

func swap_ownership(r1 Resource, r2 Resource) (Resource, Resource) {
    return r2, r1
}


func borrow_shared(r *Resource) int {

    if r.ptr != nil {
        return *r.ptr
    }
    return 0
}

func borrow_mutable(r *Resource) () {
    if r.ptr != nil {
        *r.ptr = *r.ptr + 100
    }
}

func borrow_multiple_shared(r *Resource) int {
    first := borrowShared(r)
    second := borrowShared(r)
    third := borrowShared(r)
    return first + second + third
}


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


struct lifetime_tracker {
    ref *int
    createdAt int
}

func borrow_with_lifetime(r *Resource) *int {

    return r.ptr
}


func demonstrate_lifetime_valid() int {
    r := newResource(99)
    ptr := borrowWithLifetime(&r)
    value := *ptr

    return value
}


struct boxed_resource {
    data *int
}

func create_boxed_resource(int value) BoxedResource {
    return BoxedResource{
        data: box(value),
    }
}

func consume_boxed(br BoxedResource) int {
    return *br.data

}


struct move_type {
    ptr *int
}

struct copy_type {
    value int
}

func demonstrate_move_semantics() int {

    m1 := MoveType{ ptr: box(10) }
    m2 := m1
    

    value := *m2.ptr
    return value
}

func demonstrate_copy_semantics() int {

    c1 := CopyType{ value: 10 }
    c2 := c1
    

    return c1.value + c2.value
}


struct drop_flagged_resource {
    ptr *int
    dropped bool
}

func new_drop_flagged_resource(int value) DropFlaggedResource {
    return DropFlaggedResource{
        ptr: box(value),
        dropped: false,
    }
}

func (r *DropFlaggedResource) get_value() (int, bool) {
    if r.dropped {
        return 0, false
    }
    return *r.ptr, true
}

func (r *DropFlaggedResource) drop_it() () {
    if !r.dropped {

        _ = *r.ptr
        r.dropped = true
    }
}


struct raii_resource {
    id int
    handle *int
}

func acquire_resource(int id) RAIIResource {
    return RAIIResource{
        id: id,
        handle: box(id * 1000),
    }
}

func (r *RAIIResource) use_resource() int {
    if r.handle != nil {
        return *r.handle
    }
    return 0
}

func (r RAIIResource) release_resource() () {

    if r.handle != nil {
        _ = *r.handle
    }
}


struct container {
    resources []*int
    count int
}

func (c *Container) add_to_container(int value) () {

    ptr := box(value)
    c.resources[c.count] = ptr
    c.count = c.count + 1
}

func (c *Container) get_from_container(int index) *int {
    if index < c.count {
        return c.resources[index]
    }
    return nil
}


func ownership_with_return(bool condition) Resource {
    r1 := newResource(1)
    r2 := newResource(2)
    
    if condition {
        return r1
    }
    
    return r2
}

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

