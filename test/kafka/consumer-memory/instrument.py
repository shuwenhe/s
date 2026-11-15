"""Diagnostic-only allocation counters. Never edits repository runtime/compiler."""
import pathlib,sys,shutil
root=pathlib.Path('/root/shuwen/s');out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
names=['diag_calls','diag_requested','diag_allocated','diag_collections','diag_gc_live_bytes','diag_regions']
def storage():return '\n.bss\n.balign 8\n'+''.join(f'.globl {n}\n{n}: .quad 0\n' for n in names)+'\n'
if sys.argv[2]=='seed':
 p=out/'src/runtime';p.mkdir(parents=True);(p/'linker').mkdir()
 shutil.copyfile(root/'src/runtime/linker/nostdlib.ld',p/'linker/nostdlib.ld')
 s=(root/'src/runtime/selfhost_linux_amd64.S').read_text()
 s=s.replace('s_alloc:\n','s_alloc:\n    incq diag_calls(%rip)\n    addq %rdi,diag_requested(%rip)\n',1)
 s=s.replace('    and $-16, %rdi\n','    and $-16, %rdi\n    addq %rdi,diag_allocated(%rip)\n',1)
 s=s.replace('s_region_return:\n','s_region_return:\n    incq diag_regions(%rip)\n',1)
 (p/'selfhost_linux_amd64.S').write_text(s+storage())
else:
 source=pathlib.Path(sys.argv[3]);s=source.read_text()
 assert s.count('s_native_gc_alloc:\n')==1
 s=s.replace('s_native_gc_alloc:\n','s_native_gc_alloc:\n incq diag_calls(%rip)\n addq %rdi,diag_requested(%rip)\n',1)
 s=s.replace('collect.part.0:\n','collect.part.0:\n incq diag_collections(%rip)\n',1)
 anchor='\tmovq\t(%rsp), %rdi\n\tmovl\t$33554432, %eax'
 assert s.count(anchor)==1
 s=s.replace(anchor,'\tmovq\t(%rsp), %rdi\n movq %rdi,diag_gc_live_bytes(%rip)\n\tmovl\t$33554432, %eax')
 s=s.replace('.L83:\n','.L83:\n movq $0,diag_gc_live_bytes(%rip)\n',1)
 s=s.replace('\taddq\t%rbx, allocated_since_gc(%rip)','\taddq\t%rbx, diag_allocated(%rip)\n\taddq\t%rbx, allocated_since_gc(%rip)',1)
 (out/'memory-canonical-instrumented.ir').write_text(s+storage())
