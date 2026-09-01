.section .bss
.align 8
.global s_host_argc
s_host_argc:
    .quad 0
.global s_host_argv
s_host_argv:
    .quad 0
s_heap_current:
    .quad 0
s_heap_limit:
    .quad 0
.align 8
s_byte_values_ready:
    .quad 0
s_byte_values:
    .skip 6144
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
    test $1, %rax
    jz .Lstart_exit
    sar $1, %rax
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
.global s_value_add
.type s_value_add, @function
s_value_add:
    test $1, %rdi
    jz .Lvalue_add_string
    test $1, %rsi
    jz .Lvalue_add_string
    lea -1(%rdi,%rsi), %rax
    ret
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
    jz .Lvalue_cmp_left_string
    test $1, %rsi
    jnz .Lvalue_cmp_int_or_mixed
    sar $1, %rdi
    sar $1, %rsi
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
    sar $1, %rdi
    sar $1, %rsi
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
    sar $1, %rsi
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
    sar $1, %rsi
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
    sar $1, %rdi
    jmp s_byte_value_raw
.size s_byte_string_value, .-s_byte_string_value
.global s_string_slice
.type s_string_slice, @function
s_string_slice:
    sar $1, %rsi
    sar $1, %rdx
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
    sar $1, %rsi
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
    sar $1, %rsi
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
    mov %rsi, %rbx
    cmpq $6, (%rbx)
    je .Lwrite_string_rope
    lea 16(%rbx), %rsi
    mov 8(%rbx), %rdx
    call s_write
    pop %rbx
    ret
.Lwrite_string_rope:
    mov 16(%rbx), %rsi
    call s_write_string_fd
    test %rax, %rax
    js .Lwrite_string_done
    mov 24(%rbx), %rsi
    call s_write_string_fd
.Lwrite_string_done:
    pop %rbx
    ret
.size s_write_string_fd, .-s_write_string_fd
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
    mov $1, %rax
    pop %rbx
    ret
.size s_eprintln_value, .-s_eprintln_value
.global s_int_text
.type s_int_text, @function
s_int_text:
    push %rbx
    push %r12
    push %r13
    sar $1, %rdi
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
.global s_read_file_value
.type s_read_file_value, @function
s_read_file_value:
    push %rbx
    push %r12
    mov %rdi, %rbx
    mov 8(%rbx), %rax
    lea 1(%rax), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lread_file_fail
    mov %rax, %r12
    mov %rax, %rdi
    lea 16(%rbx), %rsi
    mov 8(%rbx), %rdx
    call s_memcpy
    mov 8(%rbx), %rcx
    movb $0, (%r12,%rcx)
    mov $-100, %rdi
    mov %r12, %rsi
    xor %rdx, %rdx
    xor %rcx, %rcx
    call s_openat
    test %rax, %rax
    js .Lread_file_fail
    mov %rax, %rbx
    mov $16777233, %rdi
    call s_alloc
    test %rax, %rax
    jz .Lread_file_close_fail
    mov %rax, %r12
    movq $2, (%r12)
    movq $0, 8(%r12)
.Lread_file_loop:
    mov %rbx, %rdi
    lea 16(%r12), %rsi
    add 8(%r12), %rsi
    mov $16777216, %rdx
    sub 8(%r12), %rdx
    call s_read
    test %rax, %rax
    js .Lread_file_close_fail
    jz .Lread_file_close_ok
    add %rax, 8(%r12)
    cmpq $16777216, 8(%r12)
    jb .Lread_file_loop
.Lread_file_close_ok:
    mov %rbx, %rdi
    call s_close
    mov 8(%r12), %rcx
    movb $0, 16(%r12,%rcx)
    mov %r12, %rax
    pop %r12
    pop %rbx
    ret
.Lread_file_close_fail:
    mov %rbx, %rdi
    call s_close
.Lread_file_fail:
    xor %eax, %eax
    pop %r12
    pop %rbx
    ret
.size s_read_file_value, .-s_read_file_value
.global s_write_file_value
.type s_write_file_value, @function
s_write_file_value:
    push %rbx
    push %r12
    mov %rsi, %r12
    mov %rdi, %rbx
    mov 8(%rbx), %rax
    lea 1(%rax), %rdi
    call s_alloc
    test %rax, %rax
    jz .Lwrite_file_fail
    mov %rax, %r8
    mov %rax, %rdi
    lea 16(%rbx), %rsi
    mov 8(%rbx), %rdx
    call s_memcpy
    mov 8(%rbx), %rcx
    movb $0, (%r8,%rcx)
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
    pop %r12
    pop %rbx
    ret
.Lwrite_file_fail:
    mov $3, %rax
    pop %r12
    pop %rbx
    ret
.size s_write_file_value, .-s_write_file_value
.global s_make_executable_value
.type s_make_executable_value, @function
s_make_executable_value:
    lea 16(%rdi), %rdi
    mov $493, %rsi
    mov $90, %rax
    syscall
    test %rax, %rax
    js .Lmake_executable_fail
    mov $1, %rax
    ret
.Lmake_executable_fail:
    mov $3, %rax
    ret
.size s_make_executable_value, .-s_make_executable_value
.section .rodata
.Lnewline:
    .byte 10
.section .note.GNU-stack,"",@progbits
