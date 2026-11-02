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
	.file	"native_gc.c"
	.text
	.p2align 4
	.type	add_slab, @function
add_slab:
.LFB7:
	.cfi_startproc
	cmpq	$8192, slab_count(%rip)
	je	.L25
	pushq	%r15
	.cfi_def_cfa_offset 16
	.cfi_offset 15, -16
	movl	%edi, %ecx
	movl	$1048576, %eax
	movl	$34, %r10d
	pushq	%r14
	.cfi_def_cfa_offset 24
	.cfi_offset 14, -24
	movq	$-1, %r8
	movl	%edi, %r14d
	movl	$3, %edx
	pushq	%r13
	.cfi_def_cfa_offset 32
	.cfi_offset 13, -32
	movl	$9, %r13d
	pushq	%r12
	.cfi_def_cfa_offset 40
	.cfi_offset 12, -40
	pushq	%rbp
	.cfi_def_cfa_offset 48
	.cfi_offset 6, -48
	movq	%rdi, %rbp
	pushq	%rbx
	.cfi_def_cfa_offset 56
	.cfi_offset 3, -56
	movl	$1, %ebx
	salq	%cl, %rbx
	cmpq	%rax, %rbx
	cmovb	%rax, %rbx
	xorl	%r9d, %r9d
	xorl	%edi, %edi
	movq	%r13, %rax
	movq	%rbx, %rsi
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	movq	%rax, %r12
	leaq	-1(%rax), %rax
	cmpq	$-4097, %rax
	jbe	.L26
.L23:
	xorl	%eax, %eax
.L1:
	popq	%rbx
	.cfi_remember_state
	.cfi_restore 3
	.cfi_def_cfa_offset 48
	popq	%rbp
	.cfi_restore 6
	.cfi_def_cfa_offset 40
	popq	%r12
	.cfi_restore 12
	.cfi_def_cfa_offset 32
	popq	%r13
	.cfi_restore 13
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_restore 14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_restore 15
	.cfi_def_cfa_offset 8
	ret
	.p2align 4,,10
	.p2align 3
.L26:
	.cfi_restore_state
	movq	%rbx, %r15
	movl	%ebp, %ecx
	shrq	%cl, %r15
	leaq	4095(%r15), %rax
	andq	$-4096, %rax
	movq	%rax, %rsi
	movq	%r13, %rax
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	cmpq	$-4096, %rax
	ja	.L5
	testq	%rax, %rax
	je	.L5
	movq	slab_count(%rip), %r8
	leaq	slabs(%rip), %r11
	testq	%r8, %r8
	je	.L7
	leaq	(%r8,%r8,2), %rdx
	leaq	slabs(%rip), %r11
	movq	%r8, %rcx
	salq	$4, %rdx
	leaq	-48(%r11,%rdx), %rdx
	jmp	.L8
	.p2align 4,,10
	.p2align 3
.L10:
	movdqa	(%rdx), %xmm0
	movdqa	16(%rdx), %xmm1
	subq	$48, %rdx
	movdqa	80(%rdx), %xmm2
	movaps	%xmm0, 96(%rdx)
	movaps	%xmm1, 112(%rdx)
	movaps	%xmm2, 128(%rdx)
	testq	%rcx, %rcx
	je	.L7
.L8:
	movq	%rcx, %rdi
	subq	$1, %rcx
	cmpq	%r12, (%rdx)
	ja	.L10
.L9:
	leaq	(%rdi,%rdi,2), %rdx
	addq	$1, %r8
	salq	$4, %rdx
	movq	%r8, slab_count(%rip)
	addq	%r11, %rdx
	movq	%r12, (%rdx)
	movq	%rbx, 8(%rdx)
	movq	%rbp, 16(%rdx)
	movq	%r15, 24(%rdx)
	movq	%rax, 32(%rdx)
	movq	%rsi, 40(%rdx)
	testq	%r15, %r15
	je	.L12
	leaq	free_head(%rip), %rdi
	xorl	%edx, %edx
	movq	(%rdi,%rbp,8), %rax
	.p2align 4,,10
	.p2align 3
.L11:
	movq	%rax, %rsi
	movl	%r14d, %ecx
	movq	%rdx, %rax
	addq	$1, %rdx
	salq	%cl, %rax
	addq	%r12, %rax
	movq	%rsi, (%rax)
	cmpq	%rdx, %r15
	jne	.L11
	movq	%rax, (%rdi,%rbp,8)
	movl	$1, %eax
	jmp	.L1
	.p2align 4,,10
	.p2align 3
.L5:
	xorl	%r10d, %r10d
	xorl	%r8d, %r8d
	xorl	%r9d, %r9d
	movl	$11, %eax
	xorl	%edx, %edx
	movq	%r12, %rdi
	movq	%rbx, %rsi
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	jmp	.L23
	.p2align 4,,10
	.p2align 3
.L25:
	.cfi_def_cfa_offset 8
	.cfi_restore 3
	.cfi_restore 6
	.cfi_restore 12
	.cfi_restore 13
	.cfi_restore 14
	.cfi_restore 15
	xorl	%eax, %eax
	ret
	.p2align 4,,10
	.p2align 3
.L7:
	.cfi_def_cfa_offset 56
	.cfi_offset 3, -56
	.cfi_offset 6, -48
	.cfi_offset 12, -40
	.cfi_offset 13, -32
	.cfi_offset 14, -24
	.cfi_offset 15, -16
	xorl	%edi, %edi
	jmp	.L9
.L12:
	movl	$1, %eax
	jmp	.L1
	.cfi_endproc
.LFE7:
	.size	add_slab, .-add_slab
	.p2align 4
	.type	die, @function
die:
.LFB1:
	.cfi_startproc
	xorl	%edx, %edx
	xorl	%r10d, %r10d
	xorl	%r8d, %r8d
	xorl	%r9d, %r9d
	movl	$60, %eax
	movl	$126, %edi
	movq	%rdx, %rsi
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	.cfi_endproc
.LFE1:
	.size	die, .-die
	.p2align 4
	.type	mark, @function
mark:
.LFB4:
	.cfi_startproc
	movq	slab_count(%rip), %rcx
	testq	%rcx, %rcx
	je	.L56
	cmpq	%rdi, slabs(%rip)
	pushq	%r15
	.cfi_def_cfa_offset 16
	.cfi_offset 15, -16
	pushq	%r14
	.cfi_def_cfa_offset 24
	.cfi_offset 14, -24
	pushq	%r13
	.cfi_def_cfa_offset 32
	.cfi_offset 13, -32
	pushq	%r12
	.cfi_def_cfa_offset 40
	.cfi_offset 12, -40
	leaq	slabs(%rip), %r12
	pushq	%rbp
	.cfi_def_cfa_offset 48
	.cfi_offset 6, -48
	movq	%rdi, %rbp
	pushq	%rbx
	.cfi_def_cfa_offset 56
	.cfi_offset 3, -56
	ja	.L28
	leaq	-3(%rcx,%rcx,2), %rax
	xorl	%ebx, %ebx
	salq	$4, %rax
	addq	%r12, %rax
	movq	8(%rax), %rdx
	addq	(%rax), %rdx
	cmpq	%rdi, %rdx
	ja	.L31
	jmp	.L28
	.p2align 4,,10
	.p2align 3
.L32:
	movq	%rcx, %rax
	subq	%rbx, %rax
	shrq	%rax
	addq	%rbx, %rax
	leaq	(%rax,%rax,2), %rdx
	salq	$4, %rdx
	cmpq	%rbp, (%r12,%rdx)
	jbe	.L59
	movq	%rax, %rcx
.L31:
	cmpq	%rcx, %rbx
	jb	.L32
	testq	%rbx, %rbx
	je	.L28
	subq	$1, %rbx
	leaq	(%rbx,%rbx,2), %rax
	salq	$4, %rax
	addq	%r12, %rax
	subq	(%rax), %rbp
	cmpq	8(%rax), %rbp
	jnb	.L28
	movq	16(%rax), %rcx
	movq	32(%rax), %rsi
	shrq	%cl, %rbp
	addq	%rbp, %rsi
	cmpb	$1, (%rsi)
	jne	.L28
	movq	queue_count(%rip), %rdx
	cmpq	queue_capacity(%rip), %rdx
	movb	$2, (%rsi)
	movq	queue(%rip), %r14
	je	.L60
.L34:
	leaq	(%rbx,%rbx,2), %rax
	salq	$4, %rax
	addq	%rax, %r12
	leaq	1(%rdx), %rax
	movq	16(%r12), %rcx
	movq	%rax, queue_count(%rip)
	salq	%cl, %rbp
	addq	(%r12), %rbp
	movq	%rbp, (%r14,%rdx,8)
.L28:
	popq	%rbx
	.cfi_restore 3
	.cfi_def_cfa_offset 48
	popq	%rbp
	.cfi_restore 6
	.cfi_def_cfa_offset 40
	popq	%r12
	.cfi_restore 12
	.cfi_def_cfa_offset 32
	popq	%r13
	.cfi_restore 13
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_restore 14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_restore 15
	.cfi_def_cfa_offset 8
	ret
	.p2align 4,,10
	.p2align 3
.L56:
	ret
	.p2align 4,,10
	.p2align 3
.L59:
	.cfi_def_cfa_offset 56
	.cfi_offset 3, -56
	.cfi_offset 6, -48
	.cfi_offset 12, -40
	.cfi_offset 13, -32
	.cfi_offset 14, -24
	.cfi_offset 15, -16
	leaq	1(%rax), %rbx
	jmp	.L31
.L60:
	testq	%rdx, %rdx
	je	.L43
	leaq	(%rdx,%rdx), %r15
	movq	%r15, %rax
	shrq	$61, %rax
	jne	.L36
	cmpq	%r15, %rdx
	ja	.L36
	movq	%rdx, %rsi
	salq	$4, %rsi
.L35:
	movl	$34, %r10d
	xorl	%r9d, %r9d
	movl	$9, %eax
	xorl	%edi, %edi
	movq	$-1, %r8
	movl	$3, %edx
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	movq	%rax, %r13
	cmpq	$-4096, %rax
	ja	.L36
	movq	%rax, %r14
	testq	%rax, %rax
	je	.L36
	movq	queue(%rip), %rdi
	movq	queue_count(%rip), %rdx
	movq	%rdi, %rsi
	leaq	(%rax,%rdx,8), %r8
	subq	%rax, %rsi
	testq	%rdx, %rdx
	je	.L41
	.p2align 4,,10
	.p2align 3
.L40:
	movq	(%rsi,%rax), %rcx
	addq	$8, %rax
	movq	%rcx, -8(%rax)
	cmpq	%rax, %r8
	jne	.L40
.L41:
	testq	%rdi, %rdi
	je	.L39
	movq	queue_capacity(%rip), %rax
	xorl	%r10d, %r10d
	xorl	%r8d, %r8d
	xorl	%r9d, %r9d
	xorl	%edx, %edx
	leaq	0(,%rax,8), %rsi
	movl	$11, %eax
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	movq	queue_count(%rip), %rdx
.L39:
	movq	%r13, queue(%rip)
	movq	%r15, queue_capacity(%rip)
	jmp	.L34
.L36:
	call	die
.L43:
	movl	$32768, %esi
	movl	$4096, %r15d
	jmp	.L35
	.cfi_endproc
.LFE4:
	.size	mark, .-mark
	.p2align 4
	.type	collect.part.0, @function
collect.part.0:
.LFB9:
	.cfi_startproc
	pushq	%r15
	.cfi_def_cfa_offset 16
	.cfi_offset 15, -16
	pushq	%r14
	.cfi_def_cfa_offset 24
	.cfi_offset 14, -24
	pushq	%r13
	.cfi_def_cfa_offset 32
	.cfi_offset 13, -32
	pushq	%r12
	.cfi_def_cfa_offset 40
	.cfi_offset 12, -40
	pushq	%rbp
	.cfi_def_cfa_offset 48
	.cfi_offset 6, -48
	leaq	s_native_gc_roots_end(%rip), %rbp
	pushq	%rbx
	.cfi_def_cfa_offset 56
	.cfi_offset 3, -56
	leaq	s_native_gc_roots_begin(%rip), %rbx
	subq	$24, %rsp
	.cfi_def_cfa_offset 80
	cmpq	%rbx, %rbp
	jbe	.L65
	.p2align 4,,10
	.p2align 3
.L62:
	movq	(%rbx), %rdi
	addq	$8, %rbx
	call	mark
	cmpq	%rbx, %rbp
	ja	.L62
.L65:
	xorl	%ebp, %ebp
	movq	slab_count(%rip), %r14
	leaq	slabs(%rip), %rbx
	cmpq	$0, queue_count(%rip)
	je	.L64
	.p2align 4,,10
	.p2align 3
.L63:
	movq	queue(%rip), %rax
	movq	%r14, %rsi
	xorl	%ecx, %ecx
	movq	(%rax,%rbp,8), %r12
	jmp	.L68
	.p2align 4,,10
	.p2align 3
.L69:
	movq	%rsi, %rax
	subq	%rcx, %rax
	shrq	%rax
	addq	%rcx, %rax
	leaq	(%rax,%rax,2), %rdx
	salq	$4, %rdx
	cmpq	(%rbx,%rdx), %r12
	jnb	.L103
	movq	%rax, %rsi
.L68:
	cmpq	%rcx, %rsi
	ja	.L69
	leaq	-3(%rcx,%rcx,2), %rax
	movl	$1, %r13d
	salq	$4, %rax
	movq	16(%rbx,%rax), %rcx
	salq	%cl, %r13
	addq	%r12, %r13
	cmpq	%r13, %r12
	jnb	.L71
	.p2align 4,,10
	.p2align 3
.L70:
	movq	(%r12), %rdi
	addq	$8, %r12
	call	mark
	cmpq	%r12, %r13
	ja	.L70
.L71:
	addq	$1, %rbp
	cmpq	queue_count(%rip), %rbp
	jb	.L63
.L64:
	leaq	free_head(%rip), %r13
	movq	%r13, %rax
	leaq	472(%r13), %rdx
	.p2align 4,,10
	.p2align 3
.L66:
	movq	$0, (%rax)
	addq	$8, %rax
	cmpq	%rdx, %rax
	jne	.L66
	testq	%r14, %r14
	je	.L83
	leaq	slabs(%rip), %rbx
	movq	$0, (%rsp)
	xorl	%r14d, %r14d
	xorl	%r15d, %r15d
	movq	%rbx, 16(%rsp)
	movq	%rbx, %r12
	.p2align 4,,10
	.p2align 3
.L80:
	movq	24(%r12), %r9
	movq	(%r12), %rdi
	movq	8(%r12), %rsi
	movq	16(%r12), %r8
	movq	32(%r12), %rbx
	movq	40(%r12), %rbp
	testq	%r9, %r9
	je	.L73
	movq	%rbx, %rax
	leaq	(%r9,%rbx), %r10
	xorl	%edx, %edx
	.p2align 4,,10
	.p2align 3
.L75:
	xorl	%ecx, %ecx
	cmpb	$2, (%rax)
	sete	%cl
	addq	$1, %rax
	addq	%rcx, %rdx
	cmpq	%rax, %r10
	jne	.L75
	testq	%rdx, %rdx
	je	.L73
	movl	%r8d, %ecx
	movl	$1, %r11d
	movq	%rsi, 8(%rsp)
	xorl	%eax, %eax
	salq	%cl, %r11
	movq	(%rsp), %r10
	movl	%r8d, %ecx
	jmp	.L76
	.p2align 4,,10
	.p2align 3
.L78:
	movq	%rax, %rdx
	movb	$0, (%rbx,%rax)
	movq	0(%r13,%r8,8), %rsi
	addq	$1, %rax
	salq	%cl, %rdx
	addq	%rdi, %rdx
	movq	%rsi, (%rdx)
	movq	%rdx, 0(%r13,%r8,8)
	cmpq	%rax, %r9
	je	.L104
.L76:
	cmpb	$2, (%rbx,%rax)
	jne	.L78
	movb	$1, (%rbx,%rax)
	addq	$1, %rax
	addq	%r11, %r10
	cmpq	%rax, %r9
	jne	.L76
.L104:
	leaq	(%r14,%r14,2), %rax
	movq	8(%rsp), %rsi
	movq	%r10, (%rsp)
	addq	$1, %r14
	salq	$4, %rax
	addq	16(%rsp), %rax
	movq	%rdi, (%rax)
	movq	%rsi, 8(%rax)
	movq	%r8, 16(%rax)
	movq	%r9, 24(%rax)
	movq	%rbx, 32(%rax)
	movq	%rbp, 40(%rax)
	jmp	.L77
	.p2align 4,,10
	.p2align 3
.L103:
	leaq	1(%rax), %rcx
	jmp	.L68
	.p2align 4,,10
	.p2align 3
.L73:
	xorl	%r10d, %r10d
	xorl	%r8d, %r8d
	xorl	%r9d, %r9d
	xorl	%edx, %edx
	movl	$11, %eax
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
	movl	$11, %eax
	movq	%rbx, %rdi
	movq	%rbp, %rsi
#APP
# 22 "native_gc.c" 1
	syscall
# 0 "" 2
#NO_APP
.L77:
	addq	$1, %r15
	addq	$48, %r12
	cmpq	slab_count(%rip), %r15
	jb	.L80
	movq	(%rsp), %rdi
	movl	$33554432, %eax
	cmpq	%rax, %rdi
	cmovnb	%rdi, %rax
.L72:
	movq	%r14, slab_count(%rip)
	movq	$0, allocated_since_gc(%rip)
	movq	%rax, period(%rip)
	addq	$24, %rsp
	.cfi_remember_state
	.cfi_def_cfa_offset 56
	popq	%rbx
	.cfi_restore 3
	.cfi_def_cfa_offset 48
	popq	%rbp
	.cfi_restore 6
	.cfi_def_cfa_offset 40
	popq	%r12
	.cfi_restore 12
	.cfi_def_cfa_offset 32
	popq	%r13
	.cfi_restore 13
	.cfi_def_cfa_offset 24
	popq	%r14
	.cfi_restore 14
	.cfi_def_cfa_offset 16
	popq	%r15
	.cfi_restore 15
	.cfi_def_cfa_offset 8
	ret
.L83:
	.cfi_restore_state
	movl	$33554432, %eax
	jmp	.L72
	.cfi_endproc
.LFE9:
	.size	collect.part.0, .-collect.part.0
	.p2align 4
	.globl	s_native_gc_alloc
	.type	s_native_gc_alloc, @function
s_native_gc_alloc:
.LFB8:
	.cfi_startproc
	endbr64
	pushq	%r14
	.cfi_def_cfa_offset 16
	.cfi_offset 14, -16
	movl	$4, %ecx
	movl	$1, %eax
	pushq	%r13
	.cfi_def_cfa_offset 24
	.cfi_offset 13, -24
	pushq	%r12
	.cfi_def_cfa_offset 32
	.cfi_offset 12, -32
	movq	%rsi, %r12
	pushq	%rbp
	.cfi_def_cfa_offset 40
	.cfi_offset 6, -40
	pushq	%rbx
	.cfi_def_cfa_offset 48
	.cfi_offset 3, -48
	subq	$16, %rsp
	.cfi_def_cfa_offset 64
	jmp	.L106
	.p2align 4,,10
	.p2align 3
.L107:
	addq	$1, %rcx
	cmpq	$59, %rcx
	je	.L118
.L106:
	movq	%rax, %rbx
	movl	%ecx, %ebp
	salq	%cl, %rbx
	cmpq	%rdi, %rbx
	jb	.L107
	movq	period(%rip), %rax
	cmpq	%rax, allocated_since_gc(%rip)
	jnb	.L136
.L108:
	leaq	free_head(%rip), %r13
	movq	0(%r13,%rcx,8), %r8
	testq	%r8, %r8
	je	.L137
.L112:
	movq	(%r8), %rax
	movq	slab_count(%rip), %rsi
	leaq	slabs(%rip), %rdi
	movq	%rax, 0(%r13,%rcx,8)
	xorl	%ecx, %ecx
	jmp	.L120
	.p2align 4,,10
	.p2align 3
.L121:
	movq	%rsi, %rax
	subq	%rcx, %rax
	shrq	%rax
	addq	%rcx, %rax
	leaq	(%rax,%rax,2), %rdx
	salq	$4, %rdx
	cmpq	%r8, (%rdi,%rdx)
	jbe	.L138
	movq	%rax, %rsi
.L120:
	cmpq	%rsi, %rcx
	jb	.L121
	leaq	-3(%rcx,%rcx,2), %rax
	movl	%ebp, %ecx
	salq	$4, %rax
	addq	%rax, %rdi
	movq	%r8, %rax
	movq	32(%rdi), %rdx
	subq	(%rdi), %rax
	shrq	%cl, %rax
	movb	$1, (%rdx,%rax)
	xorl	%eax, %eax
	.p2align 4,,10
	.p2align 3
.L122:
	movq	$0, (%rax,%r8)
	addq	$8, %rax
	cmpq	%rax, %rbx
	ja	.L122
	addq	%rbx, allocated_since_gc(%rip)
	addq	$16, %rsp
	.cfi_remember_state
	.cfi_def_cfa_offset 48
	movq	%r8, %rax
	popq	%rbx
	.cfi_restore 3
	.cfi_def_cfa_offset 40
	popq	%rbp
	.cfi_restore 6
	.cfi_def_cfa_offset 32
	popq	%r12
	.cfi_restore 12
	.cfi_def_cfa_offset 24
	popq	%r13
	.cfi_restore 13
	.cfi_def_cfa_offset 16
	popq	%r14
	.cfi_restore 14
	.cfi_def_cfa_offset 8
	ret
	.p2align 4,,10
	.p2align 3
.L138:
	.cfi_restore_state
	leaq	1(%rax), %rcx
	jmp	.L120
	.p2align 4,,10
	.p2align 3
.L136:
	movq	s_native_gc_stack_top(%rip), %r14
	testq	%r14, %r14
	je	.L139
	movq	$0, queue_count(%rip)
	movq	%r12, %r13
	cmpq	%r14, %r12
	jnb	.L111
	.p2align 4,,10
	.p2align 3
.L110:
	movq	0(%r13), %rdi
	addq	$8, %r13
	movq	%rcx, 8(%rsp)
	call	mark
	cmpq	%r13, %r14
	movq	8(%rsp), %rcx
	ja	.L110
.L111:
	movq	%rcx, 8(%rsp)
	call	collect.part.0
	movq	8(%rsp), %rcx
	jmp	.L108
	.p2align 4,,10
	.p2align 3
.L137:
	movq	%rcx, %rdi
	movq	%rcx, 8(%rsp)
	call	add_slab
	movq	8(%rsp), %rcx
	testl	%eax, %eax
	je	.L113
.L135:
	movq	0(%r13,%rcx,8), %r8
	jmp	.L112
	.p2align 4,,10
	.p2align 3
.L118:
	call	die
.L139:
	movq	$0, allocated_since_gc(%rip)
	movq	$-1, period(%rip)
	jmp	.L108
.L113:
	movq	s_native_gc_stack_top(%rip), %r14
	testq	%r14, %r14
	je	.L140
	movq	$0, queue_count(%rip)
	cmpq	%r14, %r12
	jnb	.L117
	.p2align 4,,10
	.p2align 3
.L116:
	movq	(%r12), %rdi
	addq	$8, %r12
	movq	%rcx, 8(%rsp)
	call	mark
	cmpq	%r12, %r14
	movq	8(%rsp), %rcx
	ja	.L116
.L117:
	movq	%rcx, 8(%rsp)
	call	collect.part.0
	movq	8(%rsp), %rcx
.L115:
	movq	0(%r13,%rcx,8), %r8
	testq	%r8, %r8
	jne	.L112
	movq	%rcx, %rdi
	movq	%rcx, 8(%rsp)
	call	add_slab
	testl	%eax, %eax
	je	.L118
	movq	8(%rsp), %rcx
	jmp	.L135
.L140:
	movq	$0, allocated_since_gc(%rip)
	movq	$-1, period(%rip)
	jmp	.L115
	.cfi_endproc
.LFE8:
	.size	s_native_gc_alloc, .-s_native_gc_alloc
	.globl	s_native_gc_stack_top
	.bss
	.align 8
	.type	s_native_gc_stack_top, @object
	.size	s_native_gc_stack_top, 8
s_native_gc_stack_top:
	.zero	8
	.local	queue_capacity
	.comm	queue_capacity,8,8
	.local	queue_count
	.comm	queue_count,8,8
	.local	queue
	.comm	queue,8,8
	.data
	.align 8
	.type	period, @object
	.size	period, 8
period:
	.quad	33554432
	.local	allocated_since_gc
	.comm	allocated_since_gc,8,8
	.local	free_head
	.comm	free_head,472,32
	.local	slab_count
	.comm	slab_count,8,8
	.local	slabs
	.comm	slabs,393216,32
	.ident	"GCC: (Ubuntu 11.4.0-1ubuntu1~22.04.3) 11.4.0"
	.section	.note.GNU-stack,"",@progbits
	.section	.note.gnu.property,"a"
	.align 8
	.long	1f - 0f
	.long	4f - 1f
	.long	5
0:
	.string	"GNU"
1:
	.align 8
	.long	0xc0000002
	.long	3f - 2f
2:
	.long	0x3
3:
	.align 8
4:
