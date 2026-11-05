# Odd immediates retain signed 63-bit values; header 12 boxes carry full int64.
# Header 10 remains reserved for region forwarding. Boxes are immutable scalars.
.macro S_UNTAG register
    test $1, \register
    jnz 991f
    test \register, \register
    jz 991f
    cmpq $12, (\register)
    jne 991f
    mov 8(\register), \register
    jmp 992f
991:
    sar $1, \register
992:
.endm
.section .bss
.align 8
.global s_host_argc
s_host_argc:
    .quad 0
.global s_host_argv
s_host_argv:
    .quad 0
.global s_heap_current
s_heap_current:
    .quad 0
s_heap_limit:
    .quad 0
.align 8
s_byte_values_ready:
    .quad 0
s_byte_values:
    .skip 6144
.align 8
s_temp_sequence:
    .quad 0
.section .text.startup
.global _start
.type _start, @function
_start:
    xor %rbp, %rbp
    mov (%rsp), %rdi
    lea 8(%rsp), %rsi
    mov %rdi, s_host_argc(%rip)
    mov %rsi, s_host_argv(%rip)
    and $-16, %rsp
    call s_main
    S_UNTAG %rax
    push %rax
    sub $8, %rsp
    call s_os_cleanup
    add $8, %rsp
    pop %rax
.Lstart_exit:
    mov %rax, %rdi
    mov $60, %rax
    syscall
    ud2
.size _start, .-_start
.section .text
.global s_syscall6
.type s_syscall6, @function
s_syscall6:
    mov %rdi, %rax
    mov %rsi, %rdi
    mov %rdx, %rsi
    mov %rcx, %rdx
    mov %r8, %r10
    mov %r9, %r8
    mov 8(%rsp), %r9
    syscall
    ret
.size s_syscall6, .-s_syscall6
.global s_exit
.type s_exit, @function
s_exit:
    mov $60, %rax
    syscall
    ud2
.size s_exit, .-s_exit
.global s_read
.type s_read, @function
s_read:
    xor %rax, %rax
    syscall
    ret
.size s_read, .-s_read
.global s_write
.type s_write, @function
s_write:
    mov $1, %rax
    syscall
    ret
.size s_write, .-s_write
.global s_openat
.type s_openat, @function
s_openat:
    mov %rcx, %r10
    mov $257, %rax
    syscall
    ret
.size s_openat, .-s_openat
.global s_close
.type s_close, @function
s_close:
    mov $3, %rax
    syscall
    ret
.size s_close, .-s_close
.global s_mmap
.type s_mmap, @function
s_mmap:
    mov %rcx, %r10
    mov $9, %rax
    syscall
    ret
.size s_mmap, .-s_mmap
.global s_munmap
.type s_munmap, @function
s_munmap:
    mov $11, %rax
    syscall
    ret
.size s_munmap, .-s_munmap
.global s_alloc
.type s_alloc, @function
s_alloc:
    add $15, %rdi
    and $-16, %rdi
    test %rdi, %rdi
    jz .Lalloc_zero
    mov s_heap_current(%rip), %rax
    test %rax, %rax
    jnz .Lalloc_have_heap
    push %rdi
    xor %rdi, %rdi
    mov $12, %rax
    syscall
    pop %rdi
    test %rax, %rax
    js .Lalloc_fail
    mov %rax, s_heap_current(%rip)
    mov %rax, s_heap_limit(%rip)
.Lalloc_have_heap:
    mov s_heap_current(%rip), %rax
    mov %rax, %rdx
    add %rdi, %rdx
    jc .Lalloc_fail
    cmp s_heap_limit(%rip), %rdx
    jbe .Lalloc_commit
    push %rax
    push %rdx
    mov %rdx, %rdi
    add $65535, %rdi
    and $-65536, %rdi
    mov $12, %rax
    syscall
    mov %rax, %rcx
    pop %rdx
    pop %rax
    cmp %rdx, %rcx
    jb .Lalloc_fail
    mov %rcx, s_heap_limit(%rip)
.Lalloc_commit:
    mov %rdx, s_heap_current(%rip)
    ret
.Lalloc_zero:
    mov s_heap_current(%rip), %rax
    ret
.Lalloc_fail:
    xor %rax, %rax
    ret
.size s_alloc, .-s_alloc
.global s_memcpy
.type s_memcpy, @function
s_memcpy:
    mov %rdi, %rax
    mov %rdx, %rcx
    rep movsb
    ret
.size s_memcpy, .-s_memcpy
.global s_memset
.type s_memset, @function
s_memset:
    mov %rdi, %r8
    mov %rsi, %rax
    mov %rdx, %rcx
    rep stosb
    mov %r8, %rax
    ret
.size s_memset, .-s_memset
.global s_strlen
.type s_strlen, @function
s_strlen:
    xor %rax, %rax
.Lstrlen_loop:
    cmpb $0, (%rdi,%rax)
    je .Lstrlen_done
    inc %rax
    jmp .Lstrlen_loop
.Lstrlen_done:
    ret
.size s_strlen, .-s_strlen
# Return the untagged byte at an untagged string index. Rope nodes have tag 6
# and store their left/right children at offsets 16 and 24.
.type s_string_byte_raw, @function
s_string_byte_raw:
.Lstring_byte_raw_loop:
    cmpq $6, (%rdi)
    jne .Lstring_byte_raw_flat
    mov 16(%rdi), %rax
    mov 8(%rax), %rdx
    cmp %rdx, %rsi
    jb .Lstring_byte_raw_left
    sub %rdx, %rsi
    mov 24(%rdi), %rdi
    jmp .Lstring_byte_raw_loop
.Lstring_byte_raw_left:
    mov %rax, %rdi
    jmp .Lstring_byte_raw_loop
.Lstring_byte_raw_flat:
    movzbl 16(%rdi,%rsi), %eax
    ret
.size s_string_byte_raw, .-s_string_byte_raw
# Return an interned one-byte string for an untagged byte value.
.type s_byte_value_raw, @function
s_byte_value_raw:
    push %rbx
    mov %rdi, %rbx
    cmpq $0, s_byte_values_ready(%rip)
    jne .Lbyte_value_lookup
    xor %eax, %eax
    lea s_byte_values(%rip), %rdi
.Lbyte_value_init_loop:
    cmp $256, %rax
    jae .Lbyte_value_init_done
    imul $24, %rax, %rdx
    movq $2, (%rdi,%rdx)
    movq $1, 8(%rdi,%rdx)
    mov %al, 16(%rdi,%rdx)
    movb $0, 17(%rdi,%rdx)
    inc %rax
    jmp .Lbyte_value_init_loop
.Lbyte_value_init_done:
    movq $1, s_byte_values_ready(%rip)
.Lbyte_value_lookup:
    imul $24, %rbx, %rbx
    lea s_byte_values(%rip), %rax
    add %rbx, %rax
    pop %rbx
    ret
.size s_byte_value_raw, .-s_byte_value_raw
.global s_value_len
.type s_value_len, @function
s_value_len:
    test $1, %rdi
    jnz .Lvalue_len_zero
    test %rdi, %rdi
    jz .Lvalue_len_zero
    mov 8(%rdi), %rax
    lea 1(%rax,%rax), %rax
    ret
.Lvalue_len_zero:
    mov $1, %rax
    ret
.size s_value_len, .-s_value_len
.global s_array_new
.type s_array_new, @function
s_array_new:
    push %r12
    S_UNTAG %rdi
    mov %rdi, %r12
    lea 16(,%r12,8), %rdi
    call s_alloc
    test %rax, %rax
    jz .Larray_new_pop
    movq $4, (%rax)
    mov %r12, 8(%rax)
    xor %rdx, %rdx
.Larray_new_zero:
    cmp %r12, %rdx
    jae .Larray_new_pop
    movq $1, 16(%rax,%rdx,8)
    inc %rdx
    jmp .Larray_new_zero
.Larray_new_pop:
    pop %r12
    ret
.size s_array_new, .-s_array_new
.global s_array_append
.type s_array_append, @function
s_array_append:
    # Preserve source, item and length across allocation. s_alloc/syscall may
    # clobber all caller-saved registers, including rcx and rdx.
    push %rbx
    push %r12
    push %r13
    mov %rdi, %rbx
    mov %rsi, %r12
    xor %r13d, %r13d
    test %rbx, %rbx
    jz .Larray_append_allocate
    cmp $1, %rbx              # tagged nil / integer zero
    je .Larray_append_allocate
    test $1, %rbx
    jnz .Larray_append_fail
    cmpq $4, (%rbx)
    jne .Larray_append_fail
    mov 8(%rbx), %r13
.Larray_append_allocate:
    lea 3(%r13,%r13), %rdi    # tagged (old length + 1)
    call s_array_new
    test %rax, %rax
    jz .Larray_append_done
    xor %ecx, %ecx
.Larray_append_copy:
    cmp %r13, %rcx
    jae .Larray_append_store
    mov 16(%rbx,%rcx,8), %rdx
    mov %rdx, 16(%rax,%rcx,8)
    inc %rcx
    jmp .Larray_append_copy
.Larray_append_store:
    mov %r12, 16(%rax,%r13,8)
    jmp .Larray_append_done
.Larray_append_fail:
    xor %eax, %eax
.Larray_append_done:
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_array_append, .-s_array_append
.global s_value_add
.type s_value_add, @function
s_value_add:
    test $1, %rdi
    jnz .Lvalue_add_integer_left
    test %rdi, %rdi
    jz .Lvalue_add_string
    cmpq $12, (%rdi)
    jne .Lvalue_add_string
.Lvalue_add_integer_left:
    test $1, %rsi
    jnz s_integer_add
    test %rsi, %rsi
    jz .Lvalue_add_string
    cmpq $12, (%rsi)
    je s_integer_add
    jmp .Lvalue_add_string
.Lvalue_add_string:
    cmp $1, %rdi
    je .Lvalue_add_right
    cmp $1, %rsi
    je .Lvalue_add_left
    push %rbx
    push %r12
    push %r13
    mov %rdi, %rbx
    mov %rsi, %r12
    mov 8(%rbx), %r13
    add 8(%r12), %r13
    mov $32, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lvalue_add_done
    movq $6, (%rax)
    mov %r13, 8(%rax)
    mov %rbx, 16(%rax)
    mov %r12, 24(%rax)
.Lvalue_add_done:
    pop %r13
    pop %r12
    pop %rbx
    ret
.Lvalue_add_right:
    mov %rsi, %rax
    ret
.Lvalue_add_left:
    mov %rdi, %rax
    ret
.size s_value_add, .-s_value_add
.global s_value_cmp
.type s_value_cmp, @function
s_value_cmp:
    test $1, %rdi
    jnz .Lwide_cmp_check_right
    test %rdi, %rdi
    jz .Lwide_cmp_check_right
    cmpq $12, (%rdi)
    je .Lwide_cmp_left
.Lwide_cmp_check_right:
    test $1, %rsi
    jnz .Lwide_cmp_original
    test %rsi, %rsi
    jz .Lwide_cmp_original
    cmpq $12, (%rsi)
    jne .Lwide_cmp_original
    test $1, %rdi
    jnz .Lwide_cmp_numeric
    mov $-1, %rax
    ret
.Lwide_cmp_left:
    test $1, %rsi
    jnz .Lwide_cmp_numeric
    test %rsi, %rsi
    jz .Lwide_cmp_left_greater
    cmpq $12, (%rsi)
    je .Lwide_cmp_numeric
.Lwide_cmp_left_greater:
    mov $1, %rax
    ret
.Lwide_cmp_numeric:
    S_UNTAG %rdi
    S_UNTAG %rsi
    xor %eax, %eax
    cmp %rsi, %rdi
    je .Lvalue_cmp_done
    mov $-1, %rax
    jl .Lvalue_cmp_done
    mov $1, %rax
    ret
.Lwide_cmp_original:
    # Unit has no payload and uses the zero carrier, distinct from tagged int 0.
    test %rdi, %rdi
    jnz .Lvalue_cmp_nonunit_left
    xor %eax, %eax
    test %rsi, %rsi
    jz .Lvalue_cmp_done
    mov $-1, %rax
    ret
.Lvalue_cmp_nonunit_left:
    test %rsi, %rsi
    jnz .Lvalue_cmp_nonunit
    mov $1, %rax
    ret
.Lvalue_cmp_nonunit:
    test $1, %rdi
    jz .Lvalue_cmp_left_string
    test $1, %rsi
    jnz .Lvalue_cmp_int_or_mixed
    S_UNTAG %rdi
    S_UNTAG %rsi
    xor %eax, %eax
    cmp %rsi, %rdi
    je .Lvalue_cmp_done
    mov $-1, %rax
    jl .Lvalue_cmp_done
    mov $1, %rax
.Lvalue_cmp_done:
    ret
.Lvalue_cmp_int_or_mixed:
    test $1, %rdi
    jz .Lvalue_cmp_mixed_left_string
    test $1, %rsi
    jz .Lvalue_cmp_mixed_right_string
    S_UNTAG %rdi
    S_UNTAG %rsi
    xor %eax, %eax
    cmp %rsi, %rdi
    je .Lvalue_cmp_done
    mov $-1, %rax
    jl .Lvalue_cmp_done
    mov $1, %rax
    jmp .Lvalue_cmp_done
.Lvalue_cmp_left_string:
    test $1, %rsi
    jz .Lvalue_cmp_string
.Lvalue_cmp_mixed_left_string:
    mov $-1, %rax
    ret
.Lvalue_cmp_mixed_right_string:
    mov $1, %rax
    ret
.Lvalue_cmp_string:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %rbx
    mov %rsi, %r12
    xor %r13, %r13
.Lvalue_cmp_loop:
    cmp 8(%rbx), %r13
    jae .Lvalue_cmp_lengths
    cmp 8(%r12), %r13
    jae .Lvalue_cmp_lengths
    mov %rbx, %rdi
    mov %r13, %rsi
    call s_string_byte_raw
    mov %rax, %r14
    mov %r12, %rdi
    mov %r13, %rsi
    call s_string_byte_raw
    cmp %rax, %r14
    jb .Lvalue_cmp_less
    ja .Lvalue_cmp_greater
    inc %r13
    jmp .Lvalue_cmp_loop
.Lvalue_cmp_lengths:
    mov 8(%rbx), %rax
    cmp 8(%r12), %rax
    jb .Lvalue_cmp_less
    ja .Lvalue_cmp_greater
    xor %eax, %eax
    jmp .Lvalue_cmp_string_done
.Lvalue_cmp_less:
    mov $-1, %rax
    jmp .Lvalue_cmp_string_done
.Lvalue_cmp_greater:
    mov $1, %rax
.Lvalue_cmp_string_done:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_value_cmp, .-s_value_cmp
.global s_string_char_at
.type s_string_char_at, @function
s_string_char_at:
    S_UNTAG %rsi
    test %rsi, %rsi
    js .Lchar_at_fail
    cmp 8(%rdi), %rsi
    jae .Lchar_at_fail
    call s_string_byte_raw
    mov %rax, %rdi
    jmp s_byte_value_raw
.Lchar_at_fail:
    xor %eax, %eax
    ret
.size s_string_char_at, .-s_string_char_at
.global s_string_byte_at
.type s_string_byte_at, @function
s_string_byte_at:
    S_UNTAG %rsi
    test %rsi, %rsi
    js .Lbyte_at_fail
    cmp 8(%rdi), %rsi
    jae .Lbyte_at_fail
    call s_string_byte_raw
    lea 1(%rax,%rax), %rax
    ret
.Lbyte_at_fail:
    mov $1, %rax
    ret
.size s_string_byte_at, .-s_string_byte_at
.global s_byte_string_value
.type s_byte_string_value, @function
s_byte_string_value:
    S_UNTAG %rdi
    jmp s_byte_value_raw
.size s_byte_string_value, .-s_byte_string_value
.global s_string_slice
.type s_string_slice, @function
s_string_slice:
    S_UNTAG %rsi
    S_UNTAG %rdx
    test %rsi, %rsi
    js .Lslice_fail
    cmp %rsi, %rdx
    jb .Lslice_fail
    cmp 8(%rdi), %rdx
    ja .Lslice_fail
    mov %rdx, %rcx
    sub %rsi, %rcx
    cmp $1, %rcx
    jne .Lslice_alloc
    call s_string_byte_raw
    mov %rax, %rdi
    jmp s_byte_value_raw
.Lslice_alloc:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %rbx
    mov %rsi, %r12
    mov %rdx, %r13
    sub %r12, %r13
    lea 17(%r13), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lslice_pop
    movq $2, (%rax)
    mov %r13, 8(%rax)
    mov %rax, %r14
    xor %r15, %r15
.Lslice_copy_loop:
    cmp %r13, %r15
    jae .Lslice_copy_done
    mov %rbx, %rdi
    lea (%r12,%r15), %rsi
    call s_string_byte_raw
    mov %al, 16(%r14,%r15)
    inc %r15
    jmp .Lslice_copy_loop
.Lslice_copy_done:
    movb $0, 16(%r14,%r13)
    mov %r14, %rax
.Lslice_pop:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.Lslice_fail:
    xor %eax, %eax
    ret
.size s_string_slice, .-s_string_slice
.global s_index_get
.type s_index_get, @function
s_index_get:
    test %rdi, %rdi
    jz .Lindex_fail
    test $1, %rdi
    jnz .Lindex_fail
    cmpq $2, (%rdi)
    je s_string_char_at
    cmpq $6, (%rdi)
    je s_string_char_at
    cmpq $4, (%rdi)
    jne .Lindex_fail
    S_UNTAG %rsi
    test %rsi, %rsi
    js .Lindex_fail
    cmp 8(%rdi), %rsi
    jae .Lindex_fail
    mov 16(%rdi,%rsi,8), %rax
    ret
.Lindex_fail:
    mov $1, %rax
    ret
.size s_index_get, .-s_index_get
.global s_index_set
.type s_index_set, @function
s_index_set:
    test %rdi, %rdi
    jz .Lindex_set_fail
    S_UNTAG %rsi
    test %rsi, %rsi
    js .Lindex_set_fail
    cmp 8(%rdi), %rsi
    jae .Lindex_set_fail
    mov %rdx, 16(%rdi,%rsi,8)
    mov %rdx, %rax
    ret
.Lindex_set_fail:
    mov $1, %rax
    ret
.size s_index_set, .-s_index_set
.type s_from_c_string, @function
s_from_c_string:
    push %rbx
    push %r12
    mov %rdi, %rbx
    call s_strlen
    mov %rax, %r12
    lea 17(%rax), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lfrom_c_done
    movq $2, (%rax)
    mov %r12, 8(%rax)
    mov %rax, %r8
    lea 16(%rax), %rdi
    mov %rbx, %rsi
    mov %r12, %rdx
    call s_memcpy
    movb $0, 16(%r8,%r12)
    mov %r8, %rax
.Lfrom_c_done:
    pop %r12
    pop %rbx
    ret
.size s_from_c_string, .-s_from_c_string
.global s_host_args_value
.type s_host_args_value, @function
s_host_args_value:
    push %rbx
    push %r12
    push %r13
    mov s_host_argc(%rip), %r12
    mov s_host_argv(%rip), %r13
    lea 16(,%r12,8), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lhost_args_done
    mov %rax, %rbx
    movq $4, (%rbx)
    mov %r12, 8(%rbx)
    xor %r8, %r8
.Lhost_args_loop:
    cmp %r12, %r8
    jae .Lhost_args_finish
    push %r8
    mov (%r13,%r8,8), %rdi
    call s_from_c_string
    pop %r8
    mov %rax, 16(%rbx,%r8,8)
    inc %r8
    jmp .Lhost_args_loop
.Lhost_args_finish:
    mov %rbx, %rax
.Lhost_args_done:
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_host_args_value, .-s_host_args_value
.type s_write_string_fd, @function
s_write_string_fd:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %r12
    mov %rsi, %rbx
    xor %r13d, %r13d
    xor %r14d, %r14d
    xor %r15d, %r15d
    cmpq $6, (%rbx)
    jne .Lwrite_string_flat
    # A left-deep public MIR rope may contain hundreds of thousands of nodes.
    # Keep pending right children in a private growable mapping, not call frames.
    xor %edi, %edi
    mov $4096, %esi
    mov $3, %edx
    mov $34, %r10d
    mov $-1, %r8
    xor %r9d, %r9d
    mov $9, %eax
    syscall
    cmp $-4095, %rax
    jae .Lwrite_string_finish
    mov %rax, %r13
    mov $4096, %r14
.Lwrite_string_node:
    cmpq $6, (%rbx)
    jne .Lwrite_string_flat
    lea (,%r15,8), %rax
    cmp %r14, %rax
    jb .Lwrite_string_push_right
    mov %r14, %rdx
    shl $1, %rdx
    jc .Lwrite_string_no_memory
    mov %r13, %rdi
    mov %r14, %rsi
    mov $1, %r10d
    mov $25, %eax
    syscall
    cmp $-4095, %rax
    jae .Lwrite_string_finish
    mov %rax, %r13
    mov %rdx, %r14
.Lwrite_string_push_right:
    mov 24(%rbx), %rax
    mov %rax, (%r13,%r15,8)
    inc %r15
    mov 16(%rbx), %rbx
    jmp .Lwrite_string_node
.Lwrite_string_flat:
    lea 16(%rbx), %rsi
    mov 8(%rbx), %rdx
    test %rdx, %rdx
    jz .Lwrite_string_next
.Lwrite_string_bytes:
    mov %r12, %rdi
    call s_write
    cmp $-4, %rax
    je .Lwrite_string_bytes
    test %rax, %rax
    js .Lwrite_string_finish
    jz .Lwrite_string_no_progress
    add %rax, %rsi
    sub %rax, %rdx
    jnz .Lwrite_string_bytes
.Lwrite_string_next:
    test %r15, %r15
    jz .Lwrite_string_success
    dec %r15
    mov (%r13,%r15,8), %rbx
    jmp .Lwrite_string_node
.Lwrite_string_success:
    xor %eax, %eax
    jmp .Lwrite_string_finish
.Lwrite_string_no_memory:
    mov $-12, %rax
    jmp .Lwrite_string_finish
.Lwrite_string_no_progress:
    mov $-5, %rax
.Lwrite_string_finish:
    test %r13, %r13
    jz .Lwrite_string_restore
    mov %rax, %rbx
    mov %r13, %rdi
    mov %r14, %rsi
    mov $11, %eax
    syscall
    mov %rbx, %rax
.Lwrite_string_restore:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_write_string_fd, .-s_write_string_fd
.global s_println_value
.type s_println_value, @function
s_println_value:
    push %rbx
    mov %rdi, %rbx
    mov $1, %rdi
    mov %rbx, %rsi
    call s_write_string_fd
    mov $1, %rdi
    lea .Lnewline(%rip), %rsi
    mov $1, %rdx
    call s_write
    mov $1, %rax
    pop %rbx
    ret
.size s_println_value, .-s_println_value
.global s_eprintln_value
.type s_eprintln_value, @function
s_eprintln_value:
    push %rbx
    mov %rdi, %rbx
    mov $2, %rdi
    mov %rbx, %rsi
    call s_write_string_fd
    mov $2, %rdi
    lea .Lnewline(%rip), %rsi
    mov $1, %rdx
    call s_write
    xor %eax, %eax
    pop %rbx
    ret
.size s_eprintln_value, .-s_eprintln_value
.global s_int_text
.type s_int_text, @function
s_int_text:
    push %rbx
    push %r12
    push %r13
    S_UNTAG %rdi
    mov %rdi, %rbx
    mov $48, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lint_text_done
    mov %rax, %r12
    lea 47(%rax), %r13
    movb $0, (%r13)
    xor %r8, %r8
    test %rbx, %rbx
    jns .Lint_text_abs
    neg %rbx
    mov $1, %r8
.Lint_text_abs:
    mov %r13, %r9
    test %rbx, %rbx
    jnz .Lint_text_loop
    dec %r9
    movb $48, (%r9)
    jmp .Lint_text_sign
.Lint_text_loop:
    mov %rbx, %rax
    xor %rdx, %rdx
    mov $10, %rcx
    div %rcx
    add $48, %dl
    dec %r9
    mov %dl, (%r9)
    mov %rax, %rbx
    test %rbx, %rbx
    jnz .Lint_text_loop
.Lint_text_sign:
    test %r8, %r8
    jz .Lint_text_copy
    dec %r9
    movb $45, (%r9)
.Lint_text_copy:
    mov %r13, %rdx
    sub %r9, %rdx
    movq $2, (%r12)
    mov %rdx, 8(%r12)
    lea 16(%r12), %rdi
    mov %r9, %rsi
    call s_memcpy
    mov 8(%r12), %rcx
    movb $0, 16(%r12,%rcx)
    mov %r12, %rax
.Lint_text_done:
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_int_text, .-s_int_text
.global s_value_to_string
.type s_value_to_string, @function
s_value_to_string:
    test $1, %rdi
    jnz s_int_text
    test %rdi, %rdi
    jz .Lwide_to_string_done
    cmpq $12, (%rdi)
    je s_int_text
.Lwide_to_string_done:
    mov %rdi, %rax
    ret
.size s_value_to_string, .-s_value_to_string
# Convert a flat/rope S string to a private NUL-terminated OS argument.
# Reject embedded NULs so the OS never observes a silently truncated path.
.type s_string_cstr, @function
s_string_cstr:
    push %rbx
    push %r12
    push %r13
    push %r14
    sub $8, %rsp
    test %rdi, %rdi
    jz .Lcstr_fail
    test $7, %rdi
    jnz .Lcstr_fail
    cmpq $2, (%rdi)
    je .Lcstr_valid
    cmpq $6, (%rdi)
    jne .Lcstr_fail
.Lcstr_valid:
    mov %rdi, %rbx
    mov 8(%rbx), %r12
    mov %r12, %rdi
    add $1, %rdi
    jc .Lcstr_fail
    call s_alloc
    test %rax, %rax
    jz .Lcstr_fail
    mov %rax, %r13
    xor %r14d, %r14d
.Lcstr_copy:
    cmp %r12, %r14
    jae .Lcstr_finish
    mov %rbx, %rdi
    mov %r14, %rsi
    call s_string_byte_raw
    test %al, %al
    jz .Lcstr_fail
    mov %al, (%r13,%r14)
    inc %r14
    jmp .Lcstr_copy
.Lcstr_finish:
    movb $0, (%r13,%r14)
    mov %r13, %rax
    jmp .Lcstr_done
.Lcstr_fail:
    xor %eax, %eax
.Lcstr_done:
    add $8, %rsp
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_string_cstr, .-s_string_cstr
.global s_make_temp_dir_value
.type s_make_temp_dir_value, @function
s_make_temp_dir_value:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $24, %rsp
    call s_string_cstr
    test %rax, %rax
    jz .Lprivate_temp_fail
    cmpb $0, (%rax)
    je .Lprivate_temp_fail
    mov %rax, %r12
    mov %rax, %rdi
    call s_strlen
    mov %rax, %r13
    lea 48(%r13), %rdi
    cmp %r13, %rdi
    jb .Lprivate_temp_fail
    call s_alloc
    test %rax, %rax
    jz .Lprivate_temp_fail
    mov %rax, %r14
    mov %r14, %rdi
    mov %r12, %rsi
    mov %r13, %rdx
    call s_memcpy
    lea (%r14,%r13), %rdi
    lea .Lprivate_temp_prefix(%rip), %rsi
    mov $11, %rdx
    call s_memcpy
    xor %r15d, %r15d
.Lprivate_temp_try:
    lea -48(%rbp), %rdi
    mov $8, %rsi
    xor %edx, %edx
    mov $318, %eax
    syscall
    cmp $8, %rax
    je .Lprivate_temp_nonce
    mov $39, %eax
    syscall
    xor s_temp_sequence(%rip), %rax
    mov %rax, -48(%rbp)
.Lprivate_temp_nonce:
    incq s_temp_sequence(%rip)
    mov -48(%rbp), %rax
    lea 11(%r14,%r13), %rdi
    lea .Lprivate_temp_hex(%rip), %rsi
    mov $16, %ecx
.Lprivate_temp_digits:
    mov %rax, %rdx
    shr $60, %rdx
    mov (%rsi,%rdx), %dl
    mov %dl, (%rdi)
    inc %rdi
    shl $4, %rax
    dec %ecx
    jnz .Lprivate_temp_digits
    movb $0, (%rdi)
    mov %r14, %rdi
    mov $448, %esi
    mov $83, %eax
    syscall
    test %rax, %rax
    jz .Lprivate_temp_created
    cmp $-17, %rax
    jne .Lprivate_temp_fail
    inc %r15
    cmp $64, %r15
    jb .Lprivate_temp_try
    jmp .Lprivate_temp_fail
.Lprivate_temp_created:
    mov %r14, %rdi
    call s_from_c_string
    test %rax, %rax
    jnz .Lprivate_temp_done
    mov %r14, %rdi
    mov $84, %eax
    syscall
.Lprivate_temp_fail:
    lea .L_empty_string(%rip), %rax
.Lprivate_temp_done:
    add $24, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
.size s_make_temp_dir_value, .-s_make_temp_dir_value
.global s_read_file_value
.type s_read_file_value, @function
s_read_file_value:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    xor %r12d, %r12d
    xor %r13d, %r13d
    call s_string_cstr
    test %rax, %rax
    jz .Lread_file_cleanup
    mov $-100, %rdi
    mov %rax, %rsi
    xor %rdx, %rdx
    xor %rcx, %rcx
    call s_openat
    test %rax, %rax
    js .Lread_file_cleanup
    mov %rax, %rbx
    /* Grow temporary storage for streams and large assembly artifacts;
     * retain only actual bytes in the heap after reaching EOF. */
    mov $65536, %r14d
    xor %edi, %edi
    lea 17(%r14), %rsi
    mov $3, %edx
    mov $34, %ecx
    mov $-1, %r8
    xor %r9d, %r9d
    call s_mmap
    cmp $-4095, %rax
    jae .Lread_file_close_fail
    mov %rax, %r12
    movq $2, (%r12)
    movq $0, 8(%r12)
.Lread_file_loop:
    cmp %r14, 8(%r12)
    jb .Lread_file_chunk
    mov %r14, %r15
    shl $1, %r15
    jc .Lread_file_close_fail
    mov %r15, %rdx
    add $17, %rdx
    jc .Lread_file_close_fail
    mov %r12, %rdi
    lea 17(%r14), %rsi
    mov $1, %r10d           # MREMAP_MAYMOVE
    mov $25, %eax          # mremap; failure preserves the old mapping
    syscall
    cmp $-4095, %rax
    jae .Lread_file_close_fail
    mov %rax, %r12
    mov %r15, %r14
.Lread_file_chunk:
    mov %rbx, %rdi
    lea 16(%r12), %rsi
    add 8(%r12), %rsi
    mov %r14, %rdx
    sub 8(%r12), %rdx
    call s_read
    cmp $-4, %rax             # EINTR: no bytes consumed
    je .Lread_file_loop
    test %rax, %rax
    js .Lread_file_close_fail
    jz .Lread_file_close_ok
    add %rax, 8(%r12)
    jmp .Lread_file_loop
.Lread_file_close_ok:
    mov %rbx, %rdi
    call s_close
    mov 8(%r12), %rcx
    movb $0, 16(%r12,%rcx)
    lea 17(%rcx), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lread_file_cleanup
    mov %rax, %r13
    mov %rax, %rdi
    mov %r12, %rsi
    mov 8(%r12), %rdx
    add $17, %rdx
    call s_memcpy
    jmp .Lread_file_cleanup
.Lread_file_close_fail:
    mov %rbx, %rdi
    call s_close
.Lread_file_cleanup:
    test %r12, %r12
    jz .Lread_file_done
    mov %r12, %rdi
    lea 17(%r14), %rsi
    call s_munmap
.Lread_file_done:
    mov %r13, %rax
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_read_file_value, .-s_read_file_value
.global s_read_source_value
.type s_read_source_value, @function
s_read_source_value:
    sub $8, %rsp
    call s_read_file_value
    add $8, %rsp
    test %rax, %rax
    jz .Lread_source_invalid
    mov 8(%rax), %rcx
    xor %rdx, %rdx
.Lread_source_scan:
    cmp %rcx, %rdx
    jae .Lread_source_done
    cmpb $0, 16(%rax,%rdx)
    je .Lread_source_invalid
    inc %rdx
    jmp .Lread_source_scan
.Lread_source_invalid:
    lea .L_empty_string(%rip), %rax
.Lread_source_done:
    ret
.size s_read_source_value, .-s_read_source_value
.global s_write_file_value
.type s_write_file_value, @function
s_write_file_value:
    push %rbx
    push %r12
    mov %rsi, %r12
    sub $8, %rsp
    call s_string_cstr
    test %rax, %rax
    jz .Lwrite_file_fail
    mov %rax, %r8
    mov $-100, %rdi
    mov %r8, %rsi
    mov $577, %rdx
    mov $420, %rcx
    call s_openat
    test %rax, %rax
    js .Lwrite_file_fail
    mov %rax, %rbx
    mov %rbx, %rdi
    mov %r12, %rsi
    call s_write_string_fd
    push %rax
    mov %rbx, %rdi
    call s_close
    pop %rax
    test %rax, %rax
    js .Lwrite_file_fail
    mov $1, %rax
    add $8, %rsp
    pop %r12
    pop %rbx
    ret
.Lwrite_file_fail:
    mov $3, %rax
    add $8, %rsp
    pop %r12
    pop %rbx
    ret
.size s_write_file_value, .-s_write_file_value
.global s_read_result
.type s_read_result, @function
s_read_result:
    push %r12
    push %r13
    mov %rdi, %r12
    call s_read_file_value
    mov %rax, %rsi
    xor %r13d, %r13d
    test %rax, %rax
    jnz .Lread_result_wrap
    mov $1, %r13
.Lread_result_wrap:
    mov $16, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lread_result_fail
    mov %r13, (%rax)
    mov %rsi, 8(%rax)
    pop %r13
    pop %r12
    ret
.Lread_result_fail:
    xor %eax, %eax
    pop %r13
    pop %r12
    ret
.size s_read_result, .-s_read_result
.global s_write_result
.type s_write_result, @function
s_write_result:
    push %r12
    mov %rsi, %r12
    call s_write_file_value
    mov $16, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lwrite_result_fail
    movq $0, (%rax)
    movq $0, 8(%rax)
    pop %r12
    ret
.Lwrite_result_fail:
    xor %eax, %eax
    pop %r12
    ret
.size s_write_result, .-s_write_result
.global s_temp_result
.type s_temp_result, @function
s_temp_result:
    call s_make_temp_dir_value
    mov %rax, %rsi
    mov $16, %rdi
    call s_alloc
    test %rax, %rax
    jz .Ltemp_result_fail
    movq $0, (%rax)
    mov %rsi, 8(%rax)
    ret
.Ltemp_result_fail:
    xor %eax, %eax
    ret
.size s_temp_result, .-s_temp_result
.global s_make_executable_value
.type s_make_executable_value, @function
s_make_executable_value:
    sub $8, %rsp
    call s_string_cstr
    add $8, %rsp
    test %rax, %rax
    jz .Lmake_executable_fail
    mov %rax, %rdi
    mov $493, %esi
    mov $90, %eax
    syscall
    test %rax, %rax
    js .Lmake_executable_fail
    mov $1, %rax
    ret
.Lmake_executable_fail:
    mov $3, %rax
    ret
.size s_make_executable_value, .-s_make_executable_value
.global s_runtime_env_get
.type s_runtime_env_get, @function
s_runtime_env_get:
    push %rbx
    push %r12
    push %r13
    push %r14
    sub $8, %rsp
    mov %rsi, %r12
    call s_string_cstr
    test %rax, %rax
    jz .Lruntime_env_fallback
    mov %rax, %rbx
    mov %rax, %rdi
    call s_strlen
    mov %rax, %r13
    test %r13, %r13
    jz .Lruntime_env_fallback
    mov s_host_argv(%rip), %r14
    test %r14, %r14
    jz .Lruntime_env_fallback
    mov s_host_argc(%rip), %rax
    lea 8(%r14,%rax,8), %r14
.Lruntime_env_next:
    mov (%r14), %rdi
    test %rdi, %rdi
    jz .Lruntime_env_fallback
    xor %ecx, %ecx
.Lruntime_env_key:
    cmp %r13, %rcx
    jae .Lruntime_env_equals
    mov (%rdi,%rcx), %al
    test %al, %al
    jz .Lruntime_env_skip
    cmp (%rbx,%rcx), %al
    jne .Lruntime_env_skip
    inc %rcx
    jmp .Lruntime_env_key
.Lruntime_env_equals:
    cmpb $61, (%rdi,%rcx)
    jne .Lruntime_env_skip
    lea 1(%rdi,%rcx), %rdi
    call s_from_c_string
    test %rax, %rax
    jnz .Lruntime_env_done
    jmp .Lruntime_env_fallback
.Lruntime_env_skip:
    add $8, %r14
    jmp .Lruntime_env_next
.Lruntime_env_fallback:
    mov %r12, %rax
.Lruntime_env_done:
    add $8, %rsp
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_runtime_env_get, .-s_runtime_env_get
.global s_buildcfg_goarch
.type s_buildcfg_goarch, @function
s_buildcfg_goarch:
    lea .L_amd64(%rip), %rax
    ret
.size s_buildcfg_goarch, .-s_buildcfg_goarch
.global s_zero_value
.type s_zero_value, @function
s_zero_value:
    xor %eax, %eax
    ret
.size s_zero_value, .-s_zero_value
.global s_empty_string
.type s_empty_string, @function
s_empty_string:
    lea .L_empty_string(%rip), %rax
    ret
.size s_empty_string, .-s_empty_string
.global s_fn_env_get
.type s_fn_env_get, @function
s_fn_env_get:
    mov $16, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lenv_get_fail
    movq $0, (%rax)
    lea .L_empty_string(%rip), %rcx
    mov %rcx, 8(%rax)
    ret
.Lenv_get_fail:
    xor %eax, %eax
    ret
.size s_fn_env_get, .-s_fn_env_get
.global s_make_generic
.type s_make_generic, @function
s_make_generic:
    xor %eax, %eax
    ret
.size s_make_generic, .-s_make_generic
.global s_contains_text
.type s_contains_text, @function
s_contains_text:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $16, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    call s_value_len
    S_UNTAG %rax
    mov %rax, %rbx
    mov %r13, %rdi
    call s_value_len
    S_UNTAG %rax
    mov %rax, %r15
    test %r15, %r15
    jz .Lcontains_true
    cmp %r15, %rbx
    jb .Lcontains_false
    sub %r15, %rbx
    xor %r14d, %r14d
.Lcontains_outer:
    cmp %rbx, %r14
    ja .Lcontains_false
    movq $0, (%rsp)
.Lcontains_inner:
    mov (%rsp), %rsi
    cmp %r15, %rsi
    jae .Lcontains_true
    add %r14, %rsi
    mov %r12, %rdi
    call s_string_byte_raw
    mov %rax, 8(%rsp)
    mov (%rsp), %rsi
    mov %r13, %rdi
    call s_string_byte_raw
    cmp 8(%rsp), %rax
    jne .Lcontains_next
    incq (%rsp)
    jmp .Lcontains_inner
.Lcontains_next:
    inc %r14
    jmp .Lcontains_outer
.Lcontains_true:
    mov $3, %rax
    jmp .Lcontains_done
.Lcontains_false:
    mov $1, %rax
.Lcontains_done:
    add $16, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_contains_text, .-s_contains_text
.global s_host_same_file
.type s_host_same_file, @function
s_host_same_file:
    push %rbx
    push %r12
    # Linux/amd64 struct stat is 144 bytes; keep both buffers disjoint.
    # Entry rsp is 8 mod 16; 296 bytes also aligns calls to s_string_cstr.
    sub $296, %rsp
    mov %rsi, %r12
    call s_string_cstr
    test %rax, %rax
    jz .Lsame_file_false
    mov %rax, %rbx
    mov %r12, %rdi
    call s_string_cstr
    test %rax, %rax
    jz .Lsame_file_false
    mov %rax, %r12
    mov %rbx, %rdi
    mov %rsp, %rsi
    mov $4, %eax                # stat follows symbolic links
    syscall
    test %rax, %rax
    js .Lsame_file_false
    mov %r12, %rdi
    lea 144(%rsp), %rsi
    mov $4, %eax
    syscall
    test %rax, %rax
    js .Lsame_file_false
    mov 0(%rsp), %rax          # st_dev
    cmp 144(%rsp), %rax
    jne .Lsame_file_false
    mov 8(%rsp), %rax          # st_ino
    cmp 152(%rsp), %rax
    jne .Lsame_file_false
    mov $3, %rax               # tagged true
    jmp .Lsame_file_done
.Lsame_file_false:
    mov $1, %rax               # tagged false, including invalid/missing paths
.Lsame_file_done:
    add $296, %rsp
    pop %r12
    pop %rbx
    ret
.size s_host_same_file, .-s_host_same_file
.global s_host_rename_file
.type s_host_rename_file, @function
s_host_rename_file:
    push %rbx
    push %r12
    sub $8, %rsp
    mov %rsi, %r12
    call s_string_cstr
    test %rax, %rax
    jz .Lhost_rename_fail
    mov %rax, %rbx
    mov %r12, %rdi
    call s_string_cstr
    test %rax, %rax
    jz .Lhost_rename_fail
    mov %rax, %rsi
    mov %rbx, %rdi
    mov $82, %eax
    syscall
    test %rax, %rax
    js .Lhost_rename_fail
    mov $1, %rax
    jmp .Lhost_rename_done
.Lhost_rename_fail:
    mov $3, %rax
.Lhost_rename_done:
    add $8, %rsp
    pop %r12
    pop %rbx
    ret
.size s_host_rename_file, .-s_host_rename_file
.global s_host_run_argv
.type s_host_run_argv, @function
s_host_run_argv:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $40, %rsp
    test %rdi, %rdi
    jz .Lrun_argv_fail
    test $7, %rdi
    jnz .Lrun_argv_fail
    cmpq $4, (%rdi)
    jne .Lrun_argv_fail
    mov %rdi, %r12
    mov 8(%r12), %r13
    test %r13, %r13
    jz .Lrun_argv_fail
    cmp $4096, %r13
    ja .Lrun_argv_fail
    mov %r13, -80(%rbp)
    lea 8(,%r13,8), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lrun_argv_fail
    mov %rax, %r14
    xor %ebx, %ebx
.Lrun_argv_copy:
    cmp %r13, %rbx
    jae .Lrun_argv_terminate
    mov 16(%r12,%rbx,8), %rdi
    call s_string_cstr
    test %rax, %rax
    jz .Lrun_argv_fail
    mov %rax, (%r14,%rbx,8)
    inc %rbx
    jmp .Lrun_argv_copy
.Lrun_argv_terminate:
    movq $0, (%r14,%rbx,8)
    mov (%r14), %rax
    cmpb $0, (%rax)
    je .Lrun_argv_fail
    mov s_host_argv(%rip), %r15
    test %r15, %r15
    jz .Lrun_argv_fail
    mov s_host_argc(%rip), %rax
    lea 8(%r15,%rax,8), %r15
    mov $57, %eax
    syscall
    test %rax, %rax
    jz .Lrun_argv_child
    js .Lrun_argv_fail
    mov %rax, %r12
.Lrun_argv_wait:
    mov %r12, %rdi
    lea -48(%rbp), %rsi
    xor %edx, %edx
    xor %r10d, %r10d
    mov $61, %eax
    syscall
    cmp $-4, %rax
    je .Lrun_argv_wait
    test %rax, %rax
    js .Lrun_argv_fail
    mov -48(%rbp), %eax
    mov %eax, %edx
    and $127, %edx
    jnz .Lrun_argv_signal
    shr $8, %eax
    and $255, %eax
    jmp .Lrun_argv_tag
.Lrun_argv_signal:
    lea 128(%rdx), %eax
.Lrun_argv_tag:
    lea 1(%rax,%rax), %rax
    jmp .Lrun_argv_done
.Lrun_argv_child:
    mov (%r14), %r12
    xor %ecx, %ecx
.Lrun_argv_slash:
    mov (%r12,%rcx), %al
    cmp $47, %al
    je .Lrun_argv_direct
    test %al, %al
    jz .Lrun_argv_find_path
    inc %rcx
    jmp .Lrun_argv_slash
.Lrun_argv_find_path:
    mov %rcx, %r13
    mov %r15, %rbx
.Lrun_argv_env:
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lrun_argv_default_path
    cmpb $80, (%rax)
    jne .Lrun_argv_env_next
    cmpb $65, 1(%rax)
    jne .Lrun_argv_env_next
    cmpb $84, 2(%rax)
    jne .Lrun_argv_env_next
    cmpb $72, 3(%rax)
    jne .Lrun_argv_env_next
    cmpb $61, 4(%rax)
    jne .Lrun_argv_env_next
    lea 5(%rax), %rbx
    jmp .Lrun_argv_path_init
.Lrun_argv_env_next:
    add $8, %rbx
    jmp .Lrun_argv_env
.Lrun_argv_default_path:
    lea .Lrun_default_path(%rip), %rbx
.Lrun_argv_path_init:
    movq $127, -56(%rbp)
.Lrun_argv_path:
    xor %edx, %edx
.Lrun_argv_path_length:
    mov (%rbx,%rdx), %al
    test %al, %al
    jz .Lrun_argv_path_last
    cmp $58, %al
    je .Lrun_argv_path_next
    inc %rdx
    jmp .Lrun_argv_path_length
.Lrun_argv_path_next:
    lea 1(%rbx,%rdx), %rax
    mov %rax, -48(%rbp)
    jmp .Lrun_argv_path_build
.Lrun_argv_path_last:
    movq $0, -48(%rbp)
.Lrun_argv_path_build:
    mov %rdx, -64(%rbp)
    lea 2(%rdx,%r13), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lrun_argv_child_126
    mov %rax, -72(%rbp)
    mov %rax, %rdi
    mov %rbx, %rsi
    mov -64(%rbp), %rdx
    call s_memcpy
    mov -64(%rbp), %rdx
    mov -72(%rbp), %rdi
    add %rdx, %rdi
    test %rdx, %rdx
    jz .Lrun_argv_path_name
    movb $47, (%rdi)
    inc %rdi
.Lrun_argv_path_name:
    mov %r12, %rsi
    lea 1(%r13), %rdx
    call s_memcpy
    mov -72(%rbp), %rdi
    mov %r14, %rsi
    mov %r15, %rdx
    mov $59, %eax
    syscall
    cmp $-13, %rax
    jne .Lrun_argv_path_error
    movq $126, -56(%rbp)
    jmp .Lrun_argv_path_continue
.Lrun_argv_path_error:
    cmp $-2, %rax
    je .Lrun_argv_path_continue
    cmp $-20, %rax
    jne .Lrun_argv_child_126
.Lrun_argv_path_continue:
    mov -48(%rbp), %rbx
    test %rbx, %rbx
    jnz .Lrun_argv_path
    mov -56(%rbp), %rdi
    jmp .Lrun_argv_child_exit
.Lrun_argv_direct:
    mov %r12, %rdi
    mov %r14, %rsi
    mov %r15, %rdx
    mov $59, %eax
    syscall
    cmp $-2, %rax
    je .Lrun_argv_child_127
    cmp $-20, %rax
    je .Lrun_argv_child_127
.Lrun_argv_child_126:
    mov $126, %edi
    jmp .Lrun_argv_child_exit
.Lrun_argv_child_127:
    mov $127, %edi
.Lrun_argv_child_exit:
    mov $60, %eax
    syscall
    ud2
.Lrun_argv_fail:
    mov $-1, %rax
.Lrun_argv_done:
    add $40, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
.size s_host_run_argv, .-s_host_run_argv
.section .rodata
.Lnewline:
    .byte 10
.balign 8
.L_amd64:
    .quad 2
    .quad 5
    .ascii "amd64"
    .byte 0
.balign 8
.L_empty_string:
    .quad 2
    .quad 0
    .byte 0
.section .note.GNU-stack,"",@progbits

/* Bootstrap plain-value records. All public helpers return rax=value,
   rdx=0 success / 1 allocation failure / 2 invalid operation. */
.section .text
.global s_copy_begin
s_copy_begin:
    push %rbx
    mov %rdi, %rbx
    cmpq $0, s_heap_current(%rip)
    jne .Lrecord_checkpoint
    mov $16, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lrecord_begin_fail
.Lrecord_checkpoint:
    mov s_heap_current(%rip), %rax
    mov %rax, (%rbx)
    movq $1, 8(%rbx)
    mov %rbx, %rax
    xor %edx, %edx
    pop %rbx
    ret
.Lrecord_begin_fail:
    mov $1, %edx
    pop %rbx
    ret
.global s_copy_abort
s_copy_abort:
    cmpq $1, 8(%rdi)
    jne .Lrecord_abort_done
    mov (%rdi), %rax
    mov %rax, s_heap_current(%rip)
    movq $0, 8(%rdi)
.Lrecord_abort_done:
    xor %edx, %edx
    ret
.global s_copy_commit
s_copy_commit:
    movq $0, 8(%rdi)
    xor %edx, %edx
    ret

.global s_record_error
s_record_error:
    cmp $1, %rdi
    je .Lrecord_oom_exit
    lea .Lrecord_invalid_message(%rip), %rsi
    mov $.Lrecord_invalid_length, %edx
    mov $71, %r8d
    jmp .Lrecord_error_write
.Lrecord_oom_exit:
    lea .Lrecord_oom_message(%rip), %rsi
    mov $.Lrecord_oom_length, %edx
    mov $70, %r8d
.Lrecord_error_write:
    mov $2, %edi
    mov $1, %eax
    syscall
    mov %r8, %rdi
    mov $60, %eax
    syscall
    ud2

/* Internal allocation, with the outer public helper owning rollback. */
s_record_new_impl:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %r12
    mov 8(%r12), %r15
    mov %r15, %rdi
    shl $4, %rdi
    add $32, %rdi
    jc .Lrecord_new_oom
    call s_alloc
    test %rax, %rax
    jz .Lrecord_new_oom
    mov %rax, %r13
    movq $8, (%r13)
    mov (%r12), %rax
    mov %rax, 8(%r13)
    mov %r15, 16(%r13)
    lea 32(%r13), %rax
    mov %rax, 24(%r13)
    xor %r14d, %r14d
.Lrecord_new_fields:
    cmp %r15, %r14
    jae .Lrecord_new_success
    lea (%r14,%r14,2), %rbx
    lea 16(%r12,%rbx,8), %rbx
    mov %r14, %rax
    shl $4, %rax
    mov (%rbx), %rcx
    mov %rcx, 32(%r13,%rax)
    cmpq $0, 8(%rbx)
    je .Lrecord_default_scalar
    cmpq $1, 8(%rbx)
    je .Lrecord_default_string
    cmpq $2, 8(%rbx)
    je .Lrecord_default_array
    cmpq $4, 8(%rbx)
    je .Lrecord_default_unit
    cmpq $3, 8(%rbx)
    jne .Lrecord_new_invalid
    mov 16(%rbx), %rdi
    call s_record_new_impl
    test %rdx, %rdx
    jnz .Lrecord_new_done
    jmp .Lrecord_default_store
.Lrecord_default_scalar:
    mov $1, %eax
    jmp .Lrecord_default_store
.Lrecord_default_unit:
    xor %eax, %eax
    jmp .Lrecord_default_store
.Lrecord_default_string:
    lea .L_empty_string(%rip), %rax
    jmp .Lrecord_default_store
.Lrecord_default_array:
    mov $1, %edi
    call s_array_new
    test %rax, %rax
    jz .Lrecord_new_oom
.Lrecord_default_store:
    mov %r14, %rcx
    shl $4, %rcx
    mov %rax, 40(%r13,%rcx)
    inc %r14
    jmp .Lrecord_new_fields
.Lrecord_new_success:
    mov %r13, %rax
    xor %edx, %edx
    jmp .Lrecord_new_done
.Lrecord_new_invalid:
    mov $2, %edx
    jmp .Lrecord_new_done
.Lrecord_new_oom:
    xor %eax, %eax
    mov $1, %edx
.Lrecord_new_done:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret

.global s_record_new
s_record_new:
    push %rbp
    mov %rsp, %rbp
    sub $48, %rsp
    mov %rdi, -24(%rbp)
    lea -16(%rbp), %rdi
    call s_copy_begin
    test %rdx, %rdx
    jnz .Lrecord_new_public_done
    mov -24(%rbp), %rdi
    call s_record_new_impl
    mov %rax, -32(%rbp)
    mov %rdx, -40(%rbp)
    lea -16(%rbp), %rdi
    test %rdx, %rdx
    jnz .Lrecord_new_public_abort
    call s_copy_commit
    jmp .Lrecord_new_public_result
.Lrecord_new_public_abort:
    call s_copy_abort
.Lrecord_new_public_result:
    mov -32(%rbp), %rax
    mov -40(%rbp), %rdx
.Lrecord_new_public_done:
    leave
    ret

/* Return a field slot address, including the read-only __type projection. */
s_record_slot:
    push %rbx
    push %r12
    push %r13
    mov %rdi, %rbx
    mov %rsi, %r12
    test %rbx, %rbx
    jz .Lrecord_slot_invalid
    test $7, %rbx
    jnz .Lrecord_slot_invalid
    cmpq $8, (%rbx)
    jne .Lrecord_slot_invalid
    lea .Lrecord_type_key(%rip), %rdi
    call s_value_cmp
    test %rax, %rax
    jz .Lrecord_slot_type
    xor %r13d, %r13d
.Lrecord_slot_loop:
    cmp 16(%rbx), %r13
    jae .Lrecord_slot_invalid
    mov %r13, %rax
    shl $4, %rax
    add 24(%rbx), %rax
    mov (%rax), %rdi
    mov %r12, %rsi
    call s_value_cmp
    test %rax, %rax
    jz .Lrecord_slot_found
    inc %r13
    jmp .Lrecord_slot_loop
.Lrecord_slot_type:
    lea 8(%rbx), %rax
    jmp .Lrecord_slot_success
.Lrecord_slot_found:
    mov %r13, %rax
    shl $4, %rax
    add 24(%rbx), %rax
    add $8, %rax
.Lrecord_slot_success:
    xor %edx, %edx
    jmp .Lrecord_slot_done
.Lrecord_slot_invalid:
    xor %eax, %eax
    mov $2, %edx
.Lrecord_slot_done:
    pop %r13
    pop %r12
    pop %rbx
    ret
.global s_record_get
s_record_get:
    sub $8, %rsp
    call s_record_slot
    add $8, %rsp
    test %rdx, %rdx
    jnz .Lrecord_get_done
    mov (%rax), %rax
.Lrecord_get_done:
    ret
.global s_record_set
s_record_set:
    push %rbx
    push %r12
    sub $8, %rsp
    mov %rdi, %rbx
    mov %rdx, %r12
    call s_record_slot
    test %rdx, %rdx
    jnz .Lrecord_set_done
    lea 8(%rbx), %rcx
    cmp %rcx, %rax
    je .Lrecord_set_invalid
    mov %r12, (%rax)
    mov %rbx, %rax
    jmp .Lrecord_set_done
.Lrecord_set_invalid:
    mov $2, %edx
.Lrecord_set_done:
    add $8, %rsp
    pop %r12
    pop %rbx
    ret
.global s_record_type
s_record_type:
    lea .Lrecord_type_key(%rip), %rsi
    jmp s_record_get

s_value_copy_impl:
    test %rdi, %rdi
    jz .Lrecord_copy_scalar
    test $1, %rdi
    jnz .Lrecord_copy_scalar
    cmpq $8, (%rdi)
    je .Lrecord_copy_object
    cmpq $4, (%rdi)
    je .Lrecord_copy_array
.Lrecord_copy_scalar:
    mov %rdi, %rax
    xor %edx, %edx
    ret
.Lrecord_copy_object:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %r12
    mov 16(%r12), %r15
    mov %r15, %rdi
    shl $4, %rdi
    add $32, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lrecord_copy_oom
    mov %rax, %r13
    movq $8, (%r13)
    mov 8(%r12), %rax
    mov %rax, 8(%r13)
    mov %r15, 16(%r13)
    lea 32(%r13), %rax
    mov %rax, 24(%r13)
    xor %r14d, %r14d
.Lrecord_copy_fields:
    cmp %r15, %r14
    jae .Lrecord_copy_success
    mov %r14, %rbx
    shl $4, %rbx
    add 24(%r12), %rbx
    mov (%rbx), %rcx
    mov %r14, %rax
    shl $4, %rax
    mov %rcx, 32(%r13,%rax)
    mov 8(%rbx), %rdi
    call s_value_copy_impl
    test %rdx, %rdx
    jnz .Lrecord_copy_done
    mov %r14, %rcx
    shl $4, %rcx
    mov %rax, 40(%r13,%rcx)
    inc %r14
    jmp .Lrecord_copy_fields
.Lrecord_copy_array:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %r12
    mov 8(%r12), %r15
    lea 1(%r15,%r15), %rdi
    call s_array_new
    test %rax, %rax
    jz .Lrecord_copy_oom
    mov %rax, %r13
    xor %r14d, %r14d
.Lrecord_copy_elements:
    cmp %r15, %r14
    jae .Lrecord_copy_success
    mov 16(%r12,%r14,8), %rdi
    call s_value_copy_impl
    test %rdx, %rdx
    jnz .Lrecord_copy_done
    mov %rax, 16(%r13,%r14,8)
    inc %r14
    jmp .Lrecord_copy_elements
.Lrecord_copy_success:
    mov %r13, %rax
    xor %edx, %edx
    jmp .Lrecord_copy_done
.Lrecord_copy_oom:
    xor %eax, %eax
    mov $1, %edx
.Lrecord_copy_done:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.global s_value_copy
.global s_record_copy
s_record_copy:
s_value_copy:
    /* The current emitted descriptor 0 is the statically checked plain-value
       subset. Unknown descriptors are never guessed to mean copyable. */
    test %rsi, %rsi
    jnz .Lrecord_copy_bad_descriptor
    push %rbx
    mov %rdx, %rbx
    call s_value_copy_impl
    test %rdx, %rdx
    jz .Lrecord_copy_public_done
    push %rax
    push %rdx
    mov %rbx, %rdi
    call s_copy_abort
    pop %rdx
    pop %rax
.Lrecord_copy_public_done:
    pop %rbx
    ret
.Lrecord_copy_bad_descriptor:
    sub $8, %rsp
    mov %rdx, %rdi
    call s_copy_abort
    add $8, %rsp
    xor %eax, %eax
    mov $2, %edx
    ret
.global s_value_snapshot
s_value_snapshot:
    test %rdi, %rdi
    jz .Lrecord_snapshot_scalar
    test $1, %rdi
    jnz .Lrecord_snapshot_scalar
    cmpq $8, (%rdi)
    je .Lrecord_snapshot_allocate
    cmpq $4, (%rdi)
    je .Lrecord_snapshot_allocate
.Lrecord_snapshot_scalar:
    mov %rdi, %rax
    xor %edx, %edx
    ret
.Lrecord_snapshot_allocate:
    push %rbp
    mov %rsp, %rbp
    sub $32, %rsp
    mov %rdi, -24(%rbp)
    lea -16(%rbp), %rdi
    call s_copy_begin
    test %rdx, %rdx
    jnz .Lrecord_snapshot_error
    mov -24(%rbp), %rdi
    xor %esi, %esi
    lea -16(%rbp), %rdx
    call s_value_copy
    test %rdx, %rdx
    jnz .Lrecord_snapshot_error
    mov %rax, -24(%rbp)
    lea -16(%rbp), %rdi
    call s_copy_commit
    mov -24(%rbp), %rax
    leave
    ret
.Lrecord_snapshot_error:
    mov %rdx, %rdi
    call s_record_error
    ud2
.section .rodata
.balign 8
.Lrecord_type_key:
    .quad 2, 6
    .asciz "__type"
.Lrecord_oom_message:
    .ascii "native record allocation failed\n"
.set .Lrecord_oom_length, .-.Lrecord_oom_message
.Lrecord_invalid_message:
    .ascii "native record invalid operation\n"
.set .Lrecord_invalid_length, .-.Lrecord_invalid_message
.section .note.GNU-stack,"",@progbits

.section .rodata
.Lprivate_temp_prefix:
    .ascii "/.s-native-"
.Lprivate_temp_hex:
    .ascii "0123456789abcdef"
.Lrun_default_path:
    .asciz "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

/* Function-scoped temporary arenas. This is deterministic return-value
 * promotion, not a tracing collector. Only effect-free functions use it.
 * Evacuation forwards each object once, retaining sharing and cycles. */
.section .bss
.align 8
s_region_scratch: .quad 0
s_region_capacity: .quad 0
s_region_low: .quad 0
s_region_high: .quad 0
s_region_cursor: .quad 0
.section .text
.global s_region_return
.type s_region_return, @function
s_region_return:
    test %rsi, %rsi
    jz .Lregion_unchanged
    cmp s_heap_current(%rip), %rsi
    jae .Lregion_unchanged
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rdi, %rbx
    mov %rsi, %r12
    mov s_heap_current(%rip), %r13
    /* Scalar and pre-existing immutable returns need no evacuation. RET has
     * already snapshotted aggregate values into this function's arena. */
    cmp %r12, %rbx
    jb .Lregion_scalar
    cmp %r13, %rbx
    jae .Lregion_scalar
    test $1, %rbx
    jnz .Lregion_scalar
    mov %r13, %r14
    sub %r12, %r14
    cmp s_region_capacity(%rip), %r14
    jbe .Lregion_have_scratch
    /* No value points into scratch between evacuations. Release it before
     * growing, otherwise old scratch + new scratch + heap inflate the peak. */
    mov s_region_scratch(%rip), %rdi
    test %rdi, %rdi
    jz .Lregion_allocate_scratch
    mov s_region_capacity(%rip), %rsi
    mov $11, %eax
    syscall
    movq $0, s_region_scratch(%rip)
    movq $0, s_region_capacity(%rip)
.Lregion_allocate_scratch:
    mov %r14, %rsi
    add $65535, %rsi
    and $-65536, %rsi
    mov %rsi, %r15
    xor %edi, %edi
    mov $3, %edx
    mov $34, %r10d
    mov $-1, %r8
    xor %r9d, %r9d
    mov $9, %eax
    syscall
    cmp $-4095, %rax
    jae .Lregion_oom
    mov %rax, s_region_scratch(%rip)
    mov %r15, s_region_capacity(%rip)
.Lregion_have_scratch:
    mov %r12, s_region_low(%rip)
    mov %r13, s_region_high(%rip)
    mov s_region_scratch(%rip), %rax
    mov %rax, s_region_cursor(%rip)
    mov %rbx, %rdi
    call s_region_copy
    mov %rax, %rbx
    mov s_region_cursor(%rip), %r14
    sub s_region_scratch(%rip), %r14
    /* Reserve the compact live graph at the old checkpoint. */
    mov %r12, s_heap_current(%rip)
    mov %r14, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lregion_oom
    mov %rax, s_region_cursor(%rip)
    mov s_region_scratch(%rip), %rax
    mov %rax, s_region_low(%rip)
    add %r14, %rax
    mov %rax, s_region_high(%rip)
    mov %rbx, %rdi
    call s_region_copy
    jmp .Lregion_done
.Lregion_scalar:
    mov %r12, s_heap_current(%rip)
    mov %rbx, %rax
.Lregion_done:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.Lregion_oom:
    mov $1, %edi
    call s_record_error
    ud2
.Lregion_unchanged:
    mov %rdi, %rax
    ret
.size s_region_return, .-s_region_return

/* Copy a tagged graph from [low,high) into cursor. Objects outside that
 * interval are older than the checkpoint or static and remain unchanged.
 * Forwarding tag 10 occupies only discarded source storage. */
/* Iterative graph evacuation. A Cheney scan processes copied objects in
 * allocation order, so arbitrarily deep ropes do not consume the call stack. */
.type s_region_copy, @function
s_region_copy:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov s_region_cursor(%rip), %r12
    call s_region_copy_one
    mov %rax, %rbx
.Lregion_scan:
    cmp s_region_cursor(%rip), %r12
    jae .Lregion_scan_done
    mov (%r12), %r13
    mov 8(%r12), %r14
    cmp $12, %r13
    je .Lregion_scan_integer
    cmp $2, %r13
    je .Lregion_scan_flat
    cmp $6, %r13
    je .Lregion_scan_rope
    cmp $4, %r13
    je .Lregion_scan_array
    /* Record field names and schema references are static; only values move. */
    mov 16(%r12), %r14
    xor %r15d, %r15d
.Lregion_scan_fields:
    cmp %r14, %r15
    jae .Lregion_scan_record_next
    mov %r15, %rax
    shl $4, %rax
    mov 40(%r12,%rax), %rdi
    call s_region_copy_one
    mov %rax, %rcx
    mov %r15, %rax
    shl $4, %rax
    mov %rcx, 40(%r12,%rax)
    inc %r15
    jmp .Lregion_scan_fields
.Lregion_scan_record_next:
    mov %r14, %rax
    shl $4, %rax
    add $32, %rax
    jmp .Lregion_scan_next
.Lregion_scan_array:
    xor %r15d, %r15d
.Lregion_scan_elements:
    cmp %r14, %r15
    jae .Lregion_scan_array_next
    mov 16(%r12,%r15,8), %rdi
    call s_region_copy_one
    mov %rax, 16(%r12,%r15,8)
    inc %r15
    jmp .Lregion_scan_elements
.Lregion_scan_array_next:
    lea 16(,%r14,8), %rax
    jmp .Lregion_scan_next
.Lregion_scan_rope:
    mov 16(%r12), %rdi
    call s_region_copy_one
    mov %rax, 16(%r12)
    mov 24(%r12), %rdi
    call s_region_copy_one
    mov %rax, 24(%r12)
    mov $32, %eax
    jmp .Lregion_scan_next
.Lregion_scan_integer:
    mov $16, %eax
    jmp .Lregion_scan_next
.Lregion_scan_flat:
    lea 17(%r14), %rax
.Lregion_scan_next:
    add $15, %rax
    and $-16, %rax
    add %rax, %r12
    jmp .Lregion_scan
.Lregion_scan_done:
    mov %rbx, %rax
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size s_region_copy, .-s_region_copy

/* Shallow copy one object and install a forwarding address in discarded
 * source storage. The iterative scan above repairs all outgoing edges. */
.type s_region_copy_one, @function
s_region_copy_one:
    mov %rdi, %rax
    test $1, %rdi
    jnz .Lregion_one_return
    cmp s_region_low(%rip), %rdi
    jb .Lregion_one_return
    cmp s_region_high(%rip), %rdi
    jae .Lregion_one_return
    cmpq $10, (%rdi)
    je .Lregion_one_forwarded
    push %rbx
    push %r12
    push %r13
    mov %rdi, %rbx
    mov (%rbx), %r12
    mov 8(%rbx), %rcx
    cmp $12, %r12
    je .Lregion_one_integer
    cmp $2, %r12
    je .Lregion_one_flat
    cmp $6, %r12
    je .Lregion_one_rope
    cmp $4, %r12
    je .Lregion_one_array
    cmp $8, %r12
    jne .Lregion_one_invalid
    mov 16(%rbx), %rdx
    shl $4, %rdx
    add $32, %rdx
    jmp .Lregion_one_bytes
.Lregion_one_integer:
    mov $16, %edx
    jmp .Lregion_one_bytes
.Lregion_one_flat:
    lea 17(%rcx), %rdx
    jmp .Lregion_one_bytes
.Lregion_one_rope:
    mov $32, %edx
    jmp .Lregion_one_bytes
.Lregion_one_array:
    lea 16(,%rcx,8), %rdx
.Lregion_one_bytes:
    mov s_region_cursor(%rip), %r13
    lea 15(%rdx), %rax
    and $-16, %rax
    add %r13, %rax
    mov %rax, s_region_cursor(%rip)
    mov %r13, %rdi
    mov %rbx, %rsi
    call s_memcpy
    movq $10, (%rbx)
    mov %r13, 8(%rbx)
    cmp $8, %r12
    jne .Lregion_one_done
    lea 32(%r13), %rax
    mov %rax, 24(%r13)
.Lregion_one_done:
    mov %r13, %rax
    pop %r13
    pop %r12
    pop %rbx
.Lregion_one_return:
    ret
.Lregion_one_forwarded:
    mov 8(%rdi), %rax
    ret
.Lregion_one_invalid:
    mov $2, %edi
    call s_record_error
    ud2
.size s_region_copy_one, .-s_region_copy_one

.section .note.GNU-stack,"",@progbits

/* Establish a checkpoint without changing the incoming parameter ABI. */
.section .text
.global s_region_begin
.type s_region_begin, @function
s_region_begin:
    mov s_heap_current(%rip), %rax
    test %rax, %rax
    jnz .Lregion_begin_done
    push %rdi
    push %rsi
    push %rdx
    push %rcx
    push %r8
    push %r9
    sub $8, %rsp
    mov $16, %edi
    call s_alloc
    test %rax, %rax
    jz .Lregion_begin_oom
    mov s_heap_current(%rip), %rax
    add $8, %rsp
    pop %r9
    pop %r8
    pop %rcx
    pop %rdx
    pop %rsi
    pop %rdi
.Lregion_begin_done:
    ret
.Lregion_begin_oom:
    mov $1, %edi
    call s_record_error
    ud2
.size s_region_begin, .-s_region_begin
.section .note.GNU-stack,"",@progbits

.section .text

# Pack a raw signed 64-bit integer, allocating only outside the immediate range.
.global s_integer_pack
s_integer_pack:
    lea 1(%rdi,%rdi), %rax
    mov %rax, %rdx
    sar $1, %rdx
    cmp %rdi, %rdx
    je .Linteger_pack_done
    push %rdi
    mov $16, %rdi
    call s_alloc
    test %rax, %rax
    jz .Linteger_oom
    pop %rdi
    movq $12, (%rax)
    mov %rdi, 8(%rax)
.Linteger_pack_done:
    ret
.Linteger_oom:
    mov $126, %edi
    jmp s_exit

.macro S_INTEGER_BINARY name, instruction
.global s_integer_\name
s_integer_\name:
    S_UNTAG %rdi
    S_UNTAG %rsi
    \instruction %rsi, %rdi
    jmp s_integer_pack
.endm
S_INTEGER_BINARY add, add
S_INTEGER_BINARY sub, sub
S_INTEGER_BINARY mul, imul
S_INTEGER_BINARY or, or
S_INTEGER_BINARY xor, xor
S_INTEGER_BINARY and, and

.macro S_INTEGER_SHIFT name, instruction
.global s_integer_\name
s_integer_\name:
    S_UNTAG %rdi
    S_UNTAG %rsi
    mov %rsi, %rcx
    \instruction %cl, %rdi
    jmp s_integer_pack
.endm
S_INTEGER_SHIFT shl, shl
S_INTEGER_SHIFT shr, sar

.macro S_INTEGER_DIVIDE name, remainder
.global s_integer_\name
s_integer_\name:
    S_UNTAG %rdi
    S_UNTAG %rsi
    test %rsi, %rsi
    jz .Linteger_divzero
    mov %rdi, %rax
    cmp $-1, %rsi
    jne 993f
    movabs $-9223372036854775808, %rdx
    cmp %rdx, %rax
    jne 993f
    xor %edx, %edx
    jmp 994f
993:
    cqo
    idiv %rsi
994:
.if \remainder
    mov %rdx, %rdi
.else
    mov %rax, %rdi
.endif
    jmp s_integer_pack
.endm
S_INTEGER_DIVIDE div, 0
S_INTEGER_DIVIDE mod, 1
.Linteger_divzero:
    mov $86, %edi
    jmp s_exit

# Tagged seed adaptors; raw routines below use the same kernel ABI as canonical.
.text
.global s_std_clock_ns_value
s_std_clock_ns_value:
    S_UNTAG %rdi
    sub $8, %rsp
    call s_os_clock_ns
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack
.global s_std_nanosleep_value
s_std_nanosleep_value:
    S_UNTAG %rdi
    S_UNTAG %rsi
    sub $8, %rsp
    call s_os_nanosleep
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack

# Typed terminal scalar adapters for the tagged seed ABI.
.text
.global s_std_tty_size_value
s_std_tty_size_value:
    S_UNTAG %rdi
    sub $8, %rsp
    call s_os_tty_size
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack
.global s_std_terminal_enter_value
s_std_terminal_enter_value:
    S_UNTAG %rdi
    sub $8, %rsp
    call s_os_terminal_enter
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack
.global s_std_terminal_leave_value
s_std_terminal_leave_value:
    S_UNTAG %rdi
    sub $8, %rsp
    call s_os_terminal_leave
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack
.global s_std_write_value
s_std_write_value:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $16, %rsp
    S_UNTAG %rdi
    S_UNTAG %rdx
    mov %rdi, %r12
    mov %rsi, %r13
    mov %rdx, %r14
    test %r14, %r14
    js .Lstd_write_invalid
    mov %r13, %rdi
    call s_value_len
    S_UNTAG %rax
    cmp %rax, %r14
    ja .Lstd_write_invalid
    sub %r14, %rax
    mov %rax, %r15
    mov %rax, %rdi
    call s_alloc
    test %rax, %rax
    jnz .Lstd_write_allocated
    test %r15, %r15
    jnz .Lstd_write_nomem
.Lstd_write_allocated:
    mov %rax, %rbx
    movq $0, (%rsp)
.Lstd_write_copy:
    mov (%rsp), %rax
    cmp %r15, %rax
    jae .Lstd_write_syscall
    mov %r13, %rdi
    lea (%r14,%rax), %rsi
    call s_string_byte_raw
    mov (%rsp), %rcx
    mov %al, (%rbx,%rcx)
    incq (%rsp)
    jmp .Lstd_write_copy
.Lstd_write_syscall:
    mov %r12, %rdi
    mov %rbx, %rsi
    mov %r15, %rdx
    call s_os_write
    jmp .Lstd_write_done
.Lstd_write_invalid:
    mov $-22, %rax
    jmp .Lstd_write_done
.Lstd_write_nomem:
    mov $-12, %rax
.Lstd_write_done:
    add $16, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    mov %rax, %rdi
    jmp s_integer_pack


# Typed keyboard adapters for the tagged seed ABI.
.text
.global s_std_raw_enter_value
s_std_raw_enter_value:
    S_UNTAG %rdi
    sub $8, %rsp
    call s_os_raw_enter
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack
.global s_std_raw_leave_value
s_std_raw_leave_value:
    S_UNTAG %rdi
    sub $8, %rsp
    call s_os_raw_leave
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack
.global s_std_read_byte_value
s_std_read_byte_value:
    S_UNTAG %rdi
    S_UNTAG %rsi
    sub $8, %rsp
    call s_os_read_byte
    add $8, %rsp
    mov %rax, %rdi
    jmp s_integer_pack

.global s_std_string_array_concat_value
s_std_string_array_concat_value:
    cmp $1, %rdi
    jne .Lstr_concat_seed_right
    xor %edi, %edi
.Lstr_concat_seed_right:
    cmp $1, %rsi
    jne .Lstr_concat_seed_call
    xor %esi, %esi
.Lstr_concat_seed_call:
    lea s_alloc(%rip), %rdx
    mov $2, %ecx
    jmp s_value_string_array_concat

# BEGIN GENERATED NATIVE OS
# Shared freestanding OS boundary. SysV AMD64 arguments/results; negative errno.
# Generated into canonical runtime text and the seed runtime by generate-native-os.py.
.text
.global s_os_clock_ns
.type s_os_clock_ns, @function
s_os_clock_ns:
    cmp $1, %rdi
    ja .Los_clock_invalid
    sub $16, %rsp
    mov %rsp, %rsi
    mov $228, %eax
    syscall
    test %rax, %rax
    js .Los_clock_done
    mov (%rsp), %rax
    test %rax, %rax
    js .Los_clock_overflow
    imul $1000000000, %rax, %rax
    jo .Los_clock_overflow
    add 8(%rsp), %rax
    jo .Los_clock_overflow
.Los_clock_done:
    add $16, %rsp
    ret
.Los_clock_overflow:
    mov $-75, %rax
    jmp .Los_clock_done
.Los_clock_invalid:
    mov $-22, %rax
    ret
.size s_os_clock_ns, .-s_os_clock_ns

.global s_os_nanosleep
.type s_os_nanosleep, @function
s_os_nanosleep:
    # Validate even direct intrinsic callers before exposing stack timespecs.
    test %rdi, %rdi
    js .Los_sleep_invalid
    cmp $1000000000, %rsi
    jae .Los_sleep_invalid
    sub $32, %rsp
    mov %rdi, (%rsp)
    mov %rsi, 8(%rsp)
.Los_sleep_retry:
    # Initialize remaining=request as a safe fallback for injected EINTR.
    mov (%rsp), %rax
    mov %rax, 16(%rsp)
    mov 8(%rsp), %rax
    mov %rax, 24(%rsp)
    mov %rsp, %rdi
    lea 16(%rsp), %rsi
    mov $35, %eax
    syscall
    cmp $-4, %rax
    jne .Los_sleep_done
    mov 16(%rsp), %rax
    mov %rax, (%rsp)
    mov 24(%rsp), %rax
    mov %rax, 8(%rsp)
    jmp .Los_sleep_retry
.Los_sleep_done:
    add $32, %rsp
    ret
.Los_sleep_invalid:
    mov $-22, %rax
    ret
.size s_os_nanosleep, .-s_os_nanosleep

# One safe write: retry EINTR, suppress only SIGPIPE newly raised by this call,
# preserve the caller's signal mask and any previously pending SIGPIPE.
.global s_os_write
.type s_os_write, @function
s_os_write:
    cmp $2147483647, %rdi
    ja .Los_write_invalid_fd
    push %rbp
    mov %rsp, %rbp
    sub $80, %rsp
    mov %rdi, 40(%rsp)
    mov %rsi, 48(%rsp)
    mov %rdx, 56(%rsp)
    movq $4096, (%rsp)
    movq $0, 24(%rsp)
    movq $0, 32(%rsp)
    xor %edi, %edi
    mov %rsp, %rsi
    lea 8(%rsp), %rdx
    mov $8, %r10d
    mov $14, %eax
    syscall
    test %rax, %rax
    js .Los_write_return
    lea 16(%rsp), %rdi
    mov $8, %esi
    mov $127, %eax
    syscall
    test %rax, %rax
    js .Los_write_saved
    mov 16(%rsp), %rax
    and $4096, %eax
    mov %rax, 72(%rsp)
.Los_write_retry:
    mov 40(%rsp), %rdi
    mov 48(%rsp), %rsi
    mov 56(%rsp), %rdx
    mov $1, %eax
    syscall
    cmp $-4, %rax
    je .Los_write_retry
    mov %rax, 64(%rsp)
    cmp $-32, %rax
    jne .Los_write_restore
    cmpq $0, 72(%rsp)
    jne .Los_write_restore
.Los_write_drain_sigpipe:
    mov %rsp, %rdi
    xor %esi, %esi
    lea 24(%rsp), %rdx
    mov $8, %r10d
    mov $128, %eax
    syscall
    cmp $-4, %rax
    je .Los_write_drain_sigpipe
    jmp .Los_write_restore
.Los_write_saved:
    mov %rax, 64(%rsp)
.Los_write_restore:
    mov $2, %edi
    lea 8(%rsp), %rsi
    xor %edx, %edx
    mov $8, %r10d
    mov $14, %eax
    syscall
    test %rax, %rax
    js .Los_write_return
    mov 64(%rsp), %rax
.Los_write_return:
    leave
    ret
.Los_write_invalid_fd:
    mov $-22, %rax
    ret
.size s_os_write, .-s_os_write

# Canonical string adapter: int fd, {length, bytes}*, int offset.
.global s_os_write_string
.type s_os_write_string, @function
s_os_write_string:
    test %rdx, %rdx
    js .Los_write_string_invalid
    xor %ecx, %ecx
    test %rsi, %rsi
    je .Los_write_string_length
    mov (%rsi), %rcx
.Los_write_string_length:
    cmp %rcx, %rdx
    ja .Los_write_string_invalid
    test %rcx, %rcx
    je .Los_write_string_empty
    lea 8(%rsi,%rdx), %rsi
    sub %rdx, %rcx
    mov %rcx, %rdx
    jmp s_os_write
.Los_write_string_empty:
    xor %edx, %edx
    jmp s_os_write
.Los_write_string_invalid:
    mov $-22, %rax
    ret
.size s_os_write_string, .-s_os_write_string

.global s_os_tty_size
.type s_os_tty_size, @function
s_os_tty_size:
    sub $8, %rsp
.Los_tty_size_retry:
    mov %rsp, %rdx
    mov $21523, %esi
    mov $16, %eax
    syscall
    cmp $-4, %rax
    je .Los_tty_size_retry
    test %rax, %rax
    js .Los_tty_size_done
    movzwl (%rsp), %edx
    movzwl 2(%rsp), %eax
    test %edx, %edx
    je .Los_tty_size_invalid
    test %eax, %eax
    je .Los_tty_size_invalid
    shl $32, %rdx
    or %rdx, %rax
.Los_tty_size_done:
    add $8, %rsp
    ret
.Los_tty_size_invalid:
    mov $-22, %rax
    jmp .Los_tty_size_done
.size s_os_tty_size, .-s_os_tty_size

.bss
.balign 8
.Los_terminal_fd: .quad 0
.Los_terminal_token: .quad 0
.Los_terminal_sequence: .quad 0
.section .rodata
.Los_terminal_restore: .ascii "\033[?25h\033[?1049l"
.text
.global s_os_terminal_enter
.type s_os_terminal_enter, @function
s_os_terminal_enter:
    cmp $2147483647, %rdi
    ja .Los_terminal_invalid_fd
    cmpq $0, .Los_terminal_token(%rip)
    jne .Los_terminal_busy
    mov .Los_terminal_sequence(%rip), %rax
    add $1, %rax
    jo .Los_terminal_overflow
    mov %rax, .Los_terminal_sequence(%rip)
    mov %rax, .Los_terminal_token(%rip)
    mov %rdi, .Los_terminal_fd(%rip)
    ret
.Los_terminal_busy:
    mov $-16, %rax
    ret
.Los_terminal_overflow:
    mov $-75, %rax
    ret
.Los_terminal_invalid_fd:
    mov $-22, %rax
    ret
.size s_os_terminal_enter, .-s_os_terminal_enter

.global s_os_terminal_leave
.type s_os_terminal_leave, @function
s_os_terminal_leave:
    test %rdi, %rdi
    jle .Los_terminal_bad_token
    cmp .Los_terminal_token(%rip), %rdi
    jne .Los_terminal_bad_token
    push %r12
    push %r13
    push %r14
    mov .Los_terminal_fd(%rip), %r12
    xor %r13d, %r13d
.Los_terminal_leave_write:
    mov %r12, %rdi
    lea .Los_terminal_restore(%rip), %rsi
    add %r13, %rsi
    mov $14, %edx
    sub %r13, %rdx
    call s_os_write
    test %rax, %rax
    js .Los_terminal_leave_done
    je .Los_terminal_leave_zero
    add %rax, %r13
    cmp $14, %r13
    jb .Los_terminal_leave_write
    movq $0, .Los_terminal_token(%rip)
    xor %eax, %eax
.Los_terminal_leave_done:
    pop %r14
    pop %r13
    pop %r12
    ret
.Los_terminal_leave_zero:
    mov $-5, %rax
    jmp .Los_terminal_leave_done
.Los_terminal_bad_token:
    mov $-22, %rax
    ret
.size s_os_terminal_leave, .-s_os_terminal_leave

.global s_os_cleanup
.type s_os_cleanup, @function
s_os_cleanup:
    sub $8, %rsp
    mov .Los_raw_token(%rip), %rdi
    test %rdi, %rdi
    je .Los_cleanup_output
    call s_os_raw_leave
.Los_cleanup_output:
    mov .Los_terminal_token(%rip), %rdi
    test %rdi, %rdi
    je .Los_cleanup_pop
    call s_os_terminal_leave
.Los_cleanup_pop:
    add $8, %rsp
.Los_cleanup_done:
    xor %eax, %eax
    ret
.size s_os_cleanup, .-s_os_cleanup

.bss
.balign 8
.Los_raw_token: .quad 0
.Los_raw_sequence: .quad 0
.Los_raw_fd: .quad 0
.Los_raw_saved: .zero 36
.text
.global s_os_raw_enter
.type s_os_raw_enter, @function
s_os_raw_enter:
    cmp $2147483647, %rdi
    ja .Los_raw_invalid
    cmpq $0, .Los_raw_token(%rip)
    jne .Los_raw_busy
    push %r12
    push %r13
    sub $88, %rsp
    mov %rdi, %r12
    mov .Los_raw_sequence(%rip), %r13
    add $1, %r13
    jo .Los_raw_overflow
.Los_raw_get:
    mov %r12, %rdi
    mov $21505, %esi
    mov %rsp, %rdx
    mov $16, %eax
    syscall
    cmp $-4, %rax
    je .Los_raw_get
    test %rax, %rax
    js .Los_raw_enter_done
    mov %rsp, %rsi
    lea 40(%rsp), %rdi
    mov $36, %ecx
    cld
    rep movsb
    andl $-1516, 40(%rsp)
    andl $-2, 44(%rsp)
    andl $-305, 48(%rsp)
    orl $48, 48(%rsp)
    andl $-32844, 52(%rsp)
    movb $0, 62(%rsp)
    movb $1, 63(%rsp)
.Los_raw_set:
    mov %r12, %rdi
    mov $21506, %esi
    lea 40(%rsp), %rdx
    mov $16, %eax
    syscall
    cmp $-4, %rax
    je .Los_raw_set
    test %rax, %rax
    js .Los_raw_enter_done
    mov %rsp, %rsi
    lea .Los_raw_saved(%rip), %rdi
    mov $36, %ecx
    cld
    rep movsb
    mov %r12, .Los_raw_fd(%rip)
    mov %r13, .Los_raw_sequence(%rip)
    mov %r13, .Los_raw_token(%rip)
    mov %r13, %rax
.Los_raw_enter_done:
    add $88, %rsp
    pop %r13
    pop %r12
    ret
.Los_raw_overflow:
    mov $-75, %rax
    jmp .Los_raw_enter_done
.Los_raw_busy:
    mov $-16, %rax
    ret
.Los_raw_invalid:
    mov $-22, %rax
    ret
.size s_os_raw_enter, .-s_os_raw_enter

.global s_os_raw_leave
.type s_os_raw_leave, @function
s_os_raw_leave:
    test %rdi, %rdi
    jle .Los_raw_invalid_token
    cmp .Los_raw_token(%rip), %rdi
    jne .Los_raw_invalid_token
.Los_raw_restore_retry:
    mov .Los_raw_fd(%rip), %rdi
    mov $21506, %esi
    lea .Los_raw_saved(%rip), %rdx
    mov $16, %eax
    syscall
    cmp $-4, %rax
    je .Los_raw_restore_retry
    test %rax, %rax
    js .Los_raw_restore_done
    movq $0, .Los_raw_token(%rip)
.Los_raw_restore_done:
    ret
.Los_raw_invalid_token:
    mov $-22, %rax
    ret
.size s_os_raw_leave, .-s_os_raw_leave

# Poll/read a byte with an absolute monotonic deadline across interruptions.
# -4096 is EOF (outside Linux errno range); -11 is no byte before timeout.
.global s_os_read_byte
.type s_os_read_byte, @function
s_os_read_byte:
    cmp $2147483647, %rdi
    ja .Los_read_invalid
    cmp $-1, %rsi
    jl .Los_read_invalid
    cmp $2147483647, %rsi
    jg .Los_read_invalid
    push %r12
    push %r13
    push %r14
    sub $16, %rsp
    mov %rdi, %r12
    mov %rsi, %r13
    xor %r14d, %r14d
    test %r13, %r13
    jle .Los_read_poll
    mov $1, %edi
    call s_os_clock_ns
    test %rax, %rax
    js .Los_read_done
    imul $1000000, %r13, %r14
    add %rax, %r14
    jo .Los_read_overflow
.Los_read_poll:
    mov %r12d, (%rsp)
    movl $1, 4(%rsp)
    mov %rsp, %rdi
    mov $1, %esi
    mov %r13, %rdx
    mov $7, %eax
    syscall
    cmp $-4, %rax
    je .Los_read_interrupted
    test %rax, %rax
    js .Los_read_done
    je .Los_read_none
    testw $32, 6(%rsp)
    jnz .Los_read_bad_fd
    mov %r12, %rdi
    lea 8(%rsp), %rsi
    mov $1, %edx
    xor %eax, %eax
    syscall
    cmp $-4, %rax
    je .Los_read_interrupted
    test %rax, %rax
    js .Los_read_done
    je .Los_read_eof
    movzbl 8(%rsp), %eax
    jmp .Los_read_done
.Los_read_interrupted:
    test %r14, %r14
    je .Los_read_poll
    mov $1, %edi
    call s_os_clock_ns
    test %rax, %rax
    js .Los_read_done
    mov %r14, %rdx
    sub %rax, %rdx
    jle .Los_read_none
    lea 999999(%rdx), %rax
    xor %edx, %edx
    mov $1000000, %ecx
    div %rcx
    mov %rax, %r13
    jmp .Los_read_poll
.Los_read_none:
    mov $-11, %rax
    jmp .Los_read_done
.Los_read_eof:
    mov $-4096, %rax
    jmp .Los_read_done
.Los_read_bad_fd:
    mov $-9, %rax
    jmp .Los_read_done
.Los_read_overflow:
    mov $-75, %rax
.Los_read_done:
    add $16, %rsp
    pop %r14
    pop %r13
    pop %r12
    ret
.Los_read_invalid:
    mov $-22, %rax
    ret
.size s_os_read_byte, .-s_os_read_byte

# Immutable string-array concatenation. Header words: native=1, seed=2.
# rdx is the existing allocator callback, taking a raw byte count.
.global s_value_string_array_concat
.type s_value_string_array_concat, @function
s_value_string_array_concat:
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $8, %rsp
    mov %rdx, (%rsp)
    mov %rcx, %rbx
    mov %rdi, %r12
    mov %rsi, %r13
    xor %r14d, %r14d
    xor %r15d, %r15d
    test %r12, %r12
    jz .Lstr_arrays_right
    mov -8(%r12,%rbx,8), %r14
.Lstr_arrays_right:
    test %r13, %r13
    jz .Lstr_arrays_allocate
    mov -8(%r13,%rbx,8), %r15
.Lstr_arrays_allocate:
    mov %r14, %rbp
    add %r15, %rbp
    jc .Lstr_arrays_oom
    mov %rbp, %rdi
    add %rbx, %rdi
    jc .Lstr_arrays_oom
    mov %rdi, %rax
    shr $60, %rax
    jnz .Lstr_arrays_oom
    shl $3, %rdi
    call *(%rsp)
    test %rax, %rax
    jz .Lstr_arrays_oom
    cmp $2, %rbx
    jne .Lstr_arrays_header
    movq $4, (%rax)
.Lstr_arrays_header:
    mov %rbp, -8(%rax,%rbx,8)
    lea (%rax,%rbx,8), %rdi
    test %r14, %r14
    jz .Lstr_arrays_copy_right
    lea (%r12,%rbx,8), %rsi
    mov %r14, %rcx
    cld
    rep movsq
.Lstr_arrays_copy_right:
    test %r15, %r15
    jz .Lstr_arrays_done
    lea (%r13,%rbx,8), %rsi
    mov %r15, %rcx
    cld
    rep movsq
.Lstr_arrays_done:
    add $8, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
.Lstr_arrays_oom:
    mov $12, %edi
    mov $60, %eax
    syscall
    ud2
.size s_value_string_array_concat, .-s_value_string_array_concat
# END GENERATED NATIVE OS
