// Test struct literals with pointer fields (M2.6 fix)
package test.parser

struct simple_ptr {
    data* data
}

struct mixed_fields {
    ptr_field* ptr_field
    normal_field int
    another_ptr* another_ptr
}

func test_simple_literal() simple_ptr {
    simple_ptr {
        data* data,
    }
}

func test_mixed_literal() mixed_fields {
    mixed_fields {
        ptr_field* ptr_field,
        normal_field 42,
        another_ptr* another_ptr,
    }
}

func test_empty_struct() mixed_fields {
    mixed_fields {}
}
