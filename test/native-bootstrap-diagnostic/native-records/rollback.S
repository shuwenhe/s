/* Linked by the test runner against an instrumented runtime copy only. */
.section .data
.balign 8
test_budget: .quad 0
test_source: .quad 0
test_checkpoint: .quad 0
test_context: .quad 0, 0
.section .text
.global test_alloc
test_alloc:
    cmpq $0, test_budget(%rip)
    je 1f
    decq test_budget(%rip)
    jmp s_alloc
1:  xor %eax, %eax
    ret
.global s_main
s_main:
    push %rbp
    mov %rsp, %rbp
    push %r12
    push %r13
    /* Failure before first arena checkpoint must not invent a rewind point. */
    lea test_context(%rip), %rdi
    call s_copy_begin
    cmp $1, %rdx
    jne test_fail
    cmpq $0, s_heap_current(%rip)
    jne test_fail
    movq $100, test_budget(%rip)
    lea test_outer_schema(%rip), %rdi
    call s_record_new
    test %rdx, %rdx
    jnz test_fail
    mov %rax, test_source(%rip)
    xor %r12d, %r12d
1:
    mov %r12, test_budget(%rip)
    lea test_context(%rip), %rdi
    call s_copy_begin
    test %rdx, %rdx
    jnz test_fail
    mov s_heap_current(%rip), %rax
    mov %rax, test_checkpoint(%rip)
    mov test_source(%rip), %rdi
    xor %esi, %esi
    lea test_context(%rip), %rdx
    call s_value_copy
    cmp $1, %rdx
    jne test_fail
    mov s_heap_current(%rip), %rax
    cmp test_checkpoint(%rip), %rax
    jne test_fail
    cmpq $0, test_context+8(%rip)
    jne test_fail
    inc %r12
    cmp $3, %r12
    jb 1b
    /* Invalid descriptor failure also aborts the live transaction. */
    lea test_context(%rip), %rdi
    call s_copy_begin
    mov test_source(%rip), %rdi
    mov $1, %esi
    lea test_context(%rip), %rdx
    call s_value_copy
    cmp $2, %rdx
    jne test_fail
    cmpq $0, test_context+8(%rip)
    jne test_fail
    /* A successful copy has independent nested storage. */
    movq $3, test_budget(%rip)
    lea test_context(%rip), %rdi
    call s_copy_begin
    mov test_source(%rip), %rdi
    xor %esi, %esi
    lea test_context(%rip), %rdx
    call s_value_copy
    test %rdx, %rdx
    jnz test_fail
    mov %rax, %r13
    cmp test_source(%rip), %r13
    je test_fail
    lea test_context(%rip), %rdi
    call s_copy_commit
    mov test_source(%rip), %rax
    mov 24(%rax), %rax
    mov 8(%rax), %rax
    mov 24(%r13), %rcx
    cmp 8(%rcx), %rax
    je test_fail
    mov $85, %eax
    pop %r13
    pop %r12
    leave
    ret
 test_fail:
    mov $3, %eax
    pop %r13
    pop %r12
    leave
    ret
.section .rodata
.balign 8
test_inner_type: .quad 2, 5
.asciz "inner"
.balign 8
test_outer_type: .quad 2, 5
.asciz "outer"
.balign 8
test_value_key: .quad 2, 5
.asciz "value"
.balign 8
test_child_key: .quad 2, 5
.asciz "child"
.balign 8
test_array_key: .quad 2, 7
.asciz "numbers"
.balign 8
test_inner_schema:
.quad test_inner_type, 1
.quad test_value_key, 0, 0
 test_outer_schema:
.quad test_outer_type, 2
.quad test_child_key, 3, test_inner_schema
.quad test_array_key, 2, 0
