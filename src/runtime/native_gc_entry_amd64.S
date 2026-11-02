.text
.Ls_native_alloc:
 pushq %rax
 pushq %rbp
 pushq %rbx
 pushq %rcx
 pushq %rdx
 pushq %rsi
 pushq %rdi
 pushq %r8
 pushq %r9
 pushq %r10
 pushq %r11
 pushq %r12
 pushq %r13
 pushq %r14
 pushq %r15
 movq %rsp,%rsi
 movq %rsp,%rbp
 andq $-16,%rsp
 call s_native_gc_alloc
 movq %rbp,%rsp
 popq %r15
 popq %r14
 popq %r13
 popq %r12
 popq %r11
 popq %r10
 popq %r9
 popq %r8
 popq %rdi
 popq %rsi
 popq %rdx
 popq %rcx
 popq %rbx
 popq %rbp
 addq $8,%rsp
 ret
