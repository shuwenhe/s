.section .text
.globl main
main:
    # Function prologue
    push %rbp
    mov %rsp, %rbp
    # Allocate space for local variables (max 32 bytes for temp vars)
    sub $32, %rsp
    # ADD t0 = 1 + 2
    mov $1, %rax
    add $2, %rax
    # Store result in t0
    mov %rax, -8(%rbp)
    # RET: return temp var (not yet resolved)
    mov -8(%rbp), %rax
    # Function epilogue
    mov %rbp, %rsp
    pop %rbp
    ret
