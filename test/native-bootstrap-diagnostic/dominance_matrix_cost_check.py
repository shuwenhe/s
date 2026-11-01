#!/usr/bin/env python3
"""Exercise real MIR/SSA dominance code and count array elements copied."""
from pathlib import Path
import re
import os
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
seed = root / 'bin/s_seed'
size = 64

def function(text, name):
    start = re.search(r'^func ' + name + r'\(', text, re.M).start()
    end = re.search(r'^func ', text[start + 1:], re.M)
    return text[start:start + 1 + end.start()] if end else text[start:]

runtime = (root / 'src/runtime/selfhost_linux_amd64.S').read_text()
runtime = runtime.replace('.Larray_append_allocate:\n', '.Larray_append_allocate:\n    add %r13, copied_elements(%rip)\n', 1)
runtime = runtime.replace('.Lrecord_copy_array:\n', '.Lrecord_copy_array:\n    mov 8(%rdi), %rax\n    add %rax, snapshotted_elements(%rip)\n', 1)
runtime = runtime.replace('    call s_main\n', '''    call s_main
    push %rax
    mov $1, %edi
    lea copied_elements(%rip), %rsi
    mov $16, %edx
    mov $1, %eax
    syscall
    pop %rax
''', 1)
runtime += '\n.section .bss\n.balign 8\ncopied_elements: .quad 0\nsnapshotted_elements: .quad 0\n'
failures = []
with tempfile.TemporaryDirectory(prefix='s-dominance-cost-') as directory:
    work = Path(directory)
    (work / 'runtime.S').write_text(runtime)
    subprocess.run(['as', '--64', '-o', str(work / 'runtime.o'), str(work / 'runtime.S')], check=True)
    for mode in ['mir', 'ssa']:
        text = (root / f'src/cmd/compile/internal/{mode}/program.s').read_text()
        prefix = 'mir_program' if mode == 'mir' else 'ssa'
        block_type = 'mir_program_block' if mode == 'mir' else 'function_ssa_block'
        function_type = 'mir_program_function' if mode == 'mir' else 'function_ssa_function'
        suffixes = ['block_index', 'reachable_blocks', 'dominance_matrix', 'value_use_error']
        if mode == 'ssa': suffixes += ['value_index', 'value_block_index']
        definitions = '\n'.join(function(text, prefix + '_' + suffix) for suffix in suffixes)
        if mode == 'mir':
            value_structs = 'struct mir_program_parameter { int value_id }\nstruct mir_program_instruction { int[] result_ids }'
            block_field = 'mir_program_instruction[] instructions'
            function_field = 'mir_program_parameter[] params'
            definition = 'definition := mir_program_instruction { result_ids: [99] };'
            values_field = 'instructions'
        else:
            value_structs = 'struct function_ssa_value { int id }'
            block_field = 'function_ssa_value[] values'
            function_field = 'string symbol'
            definition = 'definition := function_ssa_value { id: 99 };'
            values_field = 'values'
        # Accept either physical matrix layout; the expected relation is fixed.
        rows = re.search(r'func ' + prefix + r'_dominance_matrix\([^\n]+\) int\[\]\[\]', definitions) is not None
        access = 'matrix[d][u]' if rows else f'matrix[d * {size} + u]'
        blocks = []
        for i in range(size):
            successors = [1, 2] if i == 0 else [3] if i in [1, 2, size - 2] else [] if i == size - 1 else [i + 1]
            values = ', '.join(str(7 + target * 3) for target in successors)
            successors_text = '[' + values + ']' if successors else 'int[]()'
            value_field = f', {values_field}: [definition]' if i == 1 else ''
            blocks.append(f'block_{i} := {block_type} {{ id: {7 + i * 3}, successors: {successors_text}, ballast: ballast{value_field} }};')
        entry_field = ', entry_block: 7' if mode == 'ssa' else ''
        order = list(range(size)) if mode == 'mir' else [size - 1] + list(range(size - 1))
        position = order.index(1)
        join = order.index(3)
        logical = '' if mode == 'mir' else f'definition_index = d - 1; use_index = u - 1; if d == 0 {{ definition_index = {size - 1} }}\n            if u == 0 {{ use_index = {size - 1} }}'
        nondominating = 'nondominating MIR operand' if mode == 'mir' else 'nondominating operand: '
        source = f'''package main
{value_structs}
struct {block_type} {{ int id; int[] successors; int[] ballast; {block_field} }}
struct {function_type} {{ {block_type}[] blocks; int entry_block; {function_field} }}
{definitions}
func main() int {{
    ballast := [{', '.join(str(i) for i in range(size))}];
    {definition}
    {chr(10).join(blocks)}
    blocks := [{', '.join('block_' + str(i) for i in order)}];
    f := {function_type} {{ blocks: blocks{entry_field} }}
    matrix := {prefix}_dominance_matrix(f)
    d := 0
    for d < {size} {{
        u := 0
        for u < {size} {{
            definition_index := d; use_index := u;
            {logical}
            expected := 0
            if use_index == {size - 1} || definition_index == use_index || definition_index == 0 || (definition_index >= 3 && definition_index <= use_index) {{ expected = 1 }}
            if {access} != expected {{ return 1 }}
            u = u + 1
        }}
        d = d + 1
    }}
    if {prefix}_value_use_error(f, matrix, 99, {position}, 1) != "" {{ return 2 }}
    if {prefix}_value_use_error(f, matrix, 99, {join}, 1) != "{nondominating}" {{ return 3 }}
    if {prefix}_value_use_error(f, matrix, 99, {position}, 0) == "" {{ return 4 }}
    return 42
}}
'''
        (work / f'{mode}.s').write_text(source)
        subprocess.run([str(seed), '--compile-native-unit', str(work / f'{mode}.ir'), str(work / f'{mode}.s')], cwd=root, check=True, timeout=30)
        subprocess.run([str(seed), '--emit-standalone-amd64-asm', str(work / f'{mode}.ir'), str(work / f'{mode}.S')], cwd=root, check=True, timeout=30)
        subprocess.run(['as', '--64', '-o', str(work / f'{mode}.o'), str(work / f'{mode}.S')], check=True)
        binary = work / mode
        subprocess.run(['ld', '-static', '--gc-sections', '-T', str(root / 'src/runtime/linker/nostdlib.ld'), '-o', str(binary), str(work / 'runtime.o'), str(work / f'{mode}.o')], check=True)
        result = subprocess.run([str(binary)], capture_output=True, timeout=60)
        assert result.returncode == 42, (mode, result.returncode, result.stderr)
        assert len(result.stdout) == 16, result.stdout
        copied, snapshots = struct.unpack('<QQ', result.stdout)
        compiler = os.environ.get('S_TEST_COMPILER')
        if compiler:
            artifact = work / f'{mode}.sasm'
            native = work / f'{mode}-native'
            subprocess.run([compiler, '--compile-unit', str(artifact), str(work / f'{mode}.s')], cwd=root, check=True, timeout=60)
            subprocess.run([compiler, '--emit-bin', str(artifact), str(native)], cwd=root, check=True, timeout=30)
            executed = subprocess.run([str(native)], timeout=30)
            assert executed.returncode == 42, (mode, 'canonical', executed.returncode)
        print(f'{mode}: {copied} appended and {snapshots} snapshotted elements; diamond, sparse IDs, backedge, unreachable and operand checks: PASS', flush=True)
        if snapshots >= size ** 3 * 16:
            failures.append(f'{mode} reachability copied {snapshots} snapshot elements (limit {size ** 3 * 16})')
        if copied >= size ** 3 * 4:
            failures.append(f'{mode} dominance construction copied {copied} elements (limit {size ** 3 * 4})')
assert not failures, '\n'.join(failures)
