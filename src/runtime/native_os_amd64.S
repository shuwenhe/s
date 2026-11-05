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
