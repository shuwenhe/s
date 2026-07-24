.section .rodata
.Lmessage:
    .ascii "nostdlib-runtime-ok\n"
.set message_length, .-.Lmessage

.section .text
.global s_main
.type s_main, @function
s_main:
    mov $1, %rdi
    lea .Lmessage(%rip), %rsi
    mov $message_length, %rdx
    call s_write
    xor %eax, %eax
    ret
.size s_main, .-s_main

.section .note.GNU-stack,"",@progbits
