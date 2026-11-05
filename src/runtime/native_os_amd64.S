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
    mov .Los_terminal_token(%rip), %rdi
    test %rdi, %rdi
    je .Los_cleanup_done
    jmp s_os_terminal_leave
.Los_cleanup_done:
    xor %eax, %eax
    ret
.size s_os_cleanup, .-s_os_cleanup
