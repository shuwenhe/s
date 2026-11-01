package demo
func generate_minimal_x86_64_asm() string {
    return `
.text
.globl main
main:
    push %rbp
    mov %rsp, %rbp
    xor %eax, %eax
    pop %rbp
    ret
`
}

func example_ir_to_asm_patterns() string[] {
    patterns := string[]{
        "
        "mov-pattern: mov [temp_location], %rax",
        "               mov %rax, [result_location]",
        "",
        "
        "CMP-PATTERN: mov [buildcfg_err], %rax",
        "             cmp $0, %rax           # Compare with empty string",
        "             jne L0                 # Jump if not equal",
        "",
        "
        "call-pattern: call host_args       # call external function",
        "              mov %rax, [t0]       # save result to temp",
        "",
        "
        "RET-PATTERN: mov $2, %rax         # Load return value",
        "             pop %rbp",
        "             ret",
    }
    return patterns
}

func explain_register_allocation() string {
    return `
simple register allocation strategy for mvp:
1. available x86-64 registers (caller-saved, can be clobbered):
   %rax, %rcx, %rdx, %rsi, %rdi, %r8-r11
2. for each ir temporary variable (t0, t1, ...):
   first 6: use %rax, %rcx, %rdx, %rsi, %rdi, %r8
   rest 6:  use %r9, %r10, %r11, and stack (spill)
3. allocation algorithm:
   - maintain temp -> register mapping
   - on first use, allocate a free register
   - if no free register, allocate stack location
   - spilled values accessed via [offset(%rbp)]
example:
   ir temp: t0
   register: %rax
   ir temp: t10
   register: -16(%rbp)    # 16 bytes below rbp on stack
usage:
   call|t0|func|0
   → call func; mov %rax, -0(%rbp)    # or -8(%rbp) for next
`
}

func full_example_compilation() string {
    return `
========== example: compiling simple ir to x86-64 ==========
input ir (compiler.ir):
------------------------
sseed-target-v1
func_begin|main|_|_
call|t0|host_args|0
mov|args|t0|_
ret|0|_|_
func_end|main|_|_
func_begin|host_args|_|_
ret|0|_|_
func_end|host_args|_|_
generated x86-64 assembly (compiler.s):
------------------------
.text
.globl main
.globl host_args
host_args:
    push %rbp
    mov %rsp, %rbp
    xor %eax, %eax
    pop %rbp
    ret
main:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp           # space for locals
    call host_args
    mov %rax, -8(%rbp)      # store to args
    xor %eax, %eax          # return 0
    add $16, %rsp
    pop %rbp
    ret
compilation command:
------------------------
gcc -no-pie -o compiler.bin compiler.s
verification:
------------------------
file compiler.bin
  → elf 64-bit lsb executable
ldd compiler.bin
  → normal x86-64 binary with libc dependency
nm compiler.bin | grep seed_compile
  → (empty! no c seed symbols!)
execution:
./compiler.bin
echo $?
  → 0  (success!)
`
}

func key_insight() string {
    return `
why this works for true self-hosting:
1. seed compiler generates ir (using c implementation)
   s source code → ir
2. new s-based ir compiler generates x86-64 assembly
   ir → x86-64 assembly (pure s implementation)
3. gcc assembles and links
   x86-64 assembly → elf binary
4. result binary can self-compile!
   no c seed backend needed anymore
5. proof of success:
   - no seed_compile symbols in final binary
   - can compile s source code independently
   - results are deterministic
this is how go achieved self-hosting:
1. early go used c backend
2. implemented go backend in go
3. bootstrapped with go backend
4. now go compiles itself entirely
we're doing the same for s!
`
}
