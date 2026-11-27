.text

.global s_arm64_exit
.type s_arm64_exit, %function
s_arm64_exit:
    mov x8, #93
    svc #0
    ret

.global s_arm64_write
.type s_arm64_write, %function
s_arm64_write:
    mov x8, #64
    svc #0
    ret

.global s_arm64_read
.type s_arm64_read, %function
s_arm64_read:
    mov x8, #63
    svc #0
    ret

.global s_arm64_openat
.type s_arm64_openat, %function
s_arm64_openat:
    mov x8, #56
    svc #0
    ret

.global s_arm64_close
.type s_arm64_close, %function
s_arm64_close:
    mov x8, #57
    svc #0
    ret

.global s_arm64_unlinkat
.type s_arm64_unlinkat, %function
s_arm64_unlinkat:
    mov x3, #0
    mov x8, #35
    svc #0
    ret

.global s_arm64_brk
.type s_arm64_brk, %function
s_arm64_brk:
    mov x8, #214
    svc #0
    ret

.global s_arm64_memset
.type s_arm64_memset, %function
s_arm64_memset:
    mov x3, x0
    cbz x2, .Lmemset_done
.Lmemset_loop:
    strb w1, [x3], #1
    subs x2, x2, #1
    b.ne .Lmemset_loop
.Lmemset_done:
    ret

.global s_arm64_memcpy
.type s_arm64_memcpy, %function
s_arm64_memcpy:
    mov x3, x0
    mov x4, x1
    cbz x2, .Lmemcpy_done
.Lmemcpy_loop:
    ldrb w5, [x4], #1
    strb w5, [x3], #1
    subs x2, x2, #1
    b.ne .Lmemcpy_loop
.Lmemcpy_done:
    ret

.global s_arm64_strlen
.type s_arm64_strlen, %function
s_arm64_strlen:
    mov x1, x0
    mov x0, #0
.Lstrlen_loop:
    ldrb w2, [x1], #1
    cbz w2, .Lstrlen_done
    add x0, x0, #1
    b .Lstrlen_loop
.Lstrlen_done:
    ret

.global s_arm64_streq
.type s_arm64_streq, %function
s_arm64_streq:
.Lstreq_loop:
    ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    cmp w2, w3
    b.ne .Lstreq_false
    cbnz w2, .Lstreq_loop
    mov x0, #1
    ret
.Lstreq_false:
    mov x0, #0
    ret

.global s_arm64_alloc
.type s_arm64_alloc, %function
s_arm64_alloc:
    mov x12, x0
    cbz x12, .Lalloc_fail
    add x12, x12, #15
    and x12, x12, #-16
    adrp x9, s_arm64_heap_offset
    add x9, x9, :lo12:s_arm64_heap_offset
    ldr x10, [x9]
    add x11, x10, x12
    mov x13, #65536
    cmp x11, x13
    b.gt .Lalloc_fail
    adrp x14, s_arm64_heap_arena
    add x14, x14, :lo12:s_arm64_heap_arena
    add x0, x14, x10
    str x11, [x9]
    ret
.Lalloc_fail:
    mov x0, #0
    ret

.bss
.align 3
.global s_arm64_heap_offset
s_arm64_heap_offset:
    .xword 0
.global s_arm64_heap_arena
s_arm64_heap_arena:
    .skip 65536
