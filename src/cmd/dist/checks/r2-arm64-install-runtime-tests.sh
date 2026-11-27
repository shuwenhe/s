#!/usr/bin/env bash
set -euo pipefail

root=$(cd "${S_SOURCE_ROOT:-$(dirname "$0")/../../../..}" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/s-r2-arm64-tests.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

runtime_src="$root/src/runtime/selfhost_linux_arm64.S"
runtime_obj="$tmp/runtime_arm64.o"

if [ "$(uname -m)" != "aarch64" ]; then
    echo "R2 arm64 tests require native aarch64 host" >&2
    exit 2
fi

compile_runtime() {
    as -o "$runtime_obj" "$runtime_src"
}

build_program() {
    local name=$1
    local source=$2
    local obj="$tmp/$name.o"
    local bin="$tmp/$name"
    as -o "$obj" "$source"
    ld -m aarch64linux -nostdlib -e _start -o "$bin" "$runtime_obj" "$obj"
    printf '%s\n' "$obj|$bin"
}

assert_elf_aarch64() {
    local bin=$1
    readelf -h "$bin" | grep -q 'Class:.*ELF64'
    readelf -h "$bin" | grep -q 'Machine:.*AArch64'
}

assert_run() {
    local bin=$1
    local expect_exit=$2
    local expect_out=${3:-}
    local out_file="$tmp/run.out"
    set +e
    "$bin" >"$out_file" 2>&1
    local status=$?
    set -e
    if [ "$status" -ne "$expect_exit" ]; then
        echo "unexpected exit code for $bin: got $status want $expect_exit" >&2
        cat "$out_file" >&2
        exit 1
    fi
    if [ -n "$expect_out" ]; then
        grep -Fxq "$expect_out" "$out_file" || {
            echo "unexpected output for $bin" >&2
            cat "$out_file" >&2
            exit 1
        }
    fi
}

cat > "$tmp/reloc_print.S" <<'EOF'
.global _start
.text
_start:
    adrp x1, msg
    add x1, x1, :lo12:msg
    mov x0, #1
    mov x2, #13
    bl s_arm64_write
    mov x0, #0
    bl s_arm64_exit
msg:
    .ascii "hello runtime\n"
EOF

cat > "$tmp/exit_only.S" <<'EOF'
.global _start
.text
_start:
    mov x0, #42
    bl s_arm64_exit
EOF

cat > "$tmp/memory_ops.S" <<'EOF'
.global _start
.text
_start:
    adrp x0, buf
    add x0, x0, :lo12:buf
    mov x1, #65
    mov x2, #8
    bl s_arm64_memset

    adrp x0, dst
    add x0, x0, :lo12:dst
    adrp x1, buf
    add x1, x1, :lo12:buf
    mov x2, #8
    bl s_arm64_memcpy

    adrp x0, dst
    add x0, x0, :lo12:dst
    ldrb w1, [x0]
    cmp w1, #65
    b.ne fail
    add x0, x0, #7
    ldrb w1, [x0]
    cmp w1, #65
    b.ne fail
    mov x0, #0
    bl s_arm64_exit
fail:
    mov x0, #1
    bl s_arm64_exit

.bss
.align 3
buf: .skip 8
dst: .skip 8
EOF

cat > "$tmp/alloc_ops.S" <<'EOF'
.global _start
.text
_start:
    mov x0, #32
    bl s_arm64_alloc
    mov x19, x0
    cbz x19, fail
    mov x0, #48
    bl s_arm64_alloc
    cbz x0, fail
    cmp x0, x19
    b.ls fail
    mov x0, #0
    bl s_arm64_exit
fail:
    mov x0, #2
    bl s_arm64_exit
EOF

cat > "$tmp/string_ops.S" <<'EOF'
.global _start
.text
_start:
    adrp x0, s1
    add x0, x0, :lo12:s1
    bl s_arm64_strlen
    cmp x0, #5
    b.ne fail

    adrp x0, s1
    add x0, x0, :lo12:s1
    adrp x1, s2
    add x1, x1, :lo12:s2
    bl s_arm64_streq
    cmp x0, #1
    b.ne fail

    adrp x0, s1
    add x0, x0, :lo12:s1
    adrp x1, s3
    add x1, x1, :lo12:s3
    bl s_arm64_streq
    cmp x0, #0
    b.ne fail

    mov x0, #0
    bl s_arm64_exit
fail:
    mov x0, #3
    bl s_arm64_exit

.section .rodata
s1: .asciz "hello"
s2: .asciz "hello"
s3: .asciz "world"
EOF

cat > "$tmp/file_io.S" <<'EOF'
.global _start
.text
_start:
    mov x0, #-100
    adrp x1, path
    add x1, x1, :lo12:path
    mov x2, #577
    mov x3, #420
    bl s_arm64_openat
    mov x19, x0
    cmp x19, #0
    b.lt fail

    mov x0, x19
    adrp x1, text
    add x1, x1, :lo12:text
    mov x2, #6
    bl s_arm64_write
    cmp x0, #6
    b.ne fail_close

    mov x0, x19
    bl s_arm64_close

    mov x0, #-100
    adrp x1, path
    add x1, x1, :lo12:path
    mov x2, #0
    mov x3, #0
    bl s_arm64_openat
    mov x19, x0
    cmp x19, #0
    b.lt fail

    mov x0, x19
    adrp x1, buf
    add x1, x1, :lo12:buf
    mov x2, #6
    bl s_arm64_read
    cmp x0, #6
    b.ne fail_close

    mov x0, x19
    bl s_arm64_close

    adrp x0, buf
    add x0, x0, :lo12:buf
    adrp x1, text
    add x1, x1, :lo12:text
    bl s_arm64_streq
    cmp x0, #1
    b.ne fail

    mov x0, #-100
    adrp x1, path
    add x1, x1, :lo12:path
    mov x2, #0
    bl s_arm64_unlinkat

    mov x0, #0
    bl s_arm64_exit

fail_close:
    mov x0, x19
    bl s_arm64_close
fail:
    mov x0, #4
    bl s_arm64_exit

.section .rodata
path: .asciz "/tmp/s_r2_arm64_io.txt"
text: .asciz "abc123"
.bss
.align 3
buf: .skip 16
EOF

compile_runtime

reloc_pair=$(build_program reloc_print "$tmp/reloc_print.S")
reloc_obj=${reloc_pair%%|*}
reloc_bin=${reloc_pair##*|}
readelf -r "$reloc_obj" | grep -q 'R_AARCH64'
assert_elf_aarch64 "$reloc_bin"
readelf -S "$reloc_bin" >/dev/null
readelf -l "$reloc_bin" >/dev/null
assert_run "$reloc_bin" 0 "hello runtime"

exit_pair=$(build_program exit_only "$tmp/exit_only.S")
exit_bin=${exit_pair##*|}
assert_elf_aarch64 "$exit_bin"
assert_run "$exit_bin" 42

mem_pair=$(build_program memory_ops "$tmp/memory_ops.S")
mem_bin=${mem_pair##*|}
assert_run "$mem_bin" 0

alloc_pair=$(build_program alloc_ops "$tmp/alloc_ops.S")
alloc_bin=${alloc_pair##*|}
assert_run "$alloc_bin" 0

str_pair=$(build_program string_ops "$tmp/string_ops.S")
str_bin=${str_pair##*|}
assert_run "$str_bin" 0

io_pair=$(build_program file_io "$tmp/file_io.S")
io_bin=${io_pair##*|}
assert_run "$io_bin" 0

echo "R2 arm64 install/runtime checks passed."
