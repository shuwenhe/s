#!/usr/bin/env python3
"""Bounded production MIR validator/copy profiling. Args: OUTPUT BLOCKS [validate|lookups|operands].
S_PROFILE_REVISION selects a baseline. Instrumentation is confined to diagnostic assembly.
"""
from pathlib import Path
import re,subprocess,json,time,resource,struct,sys,os
root=Path(__file__).resolve().parents[2]; out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
size=int(sys.argv[2]); mode=sys.argv[3] if len(sys.argv)>3 else 'validate'
texts='\n'.join(subprocess.check_output(['git','show',os.environ['S_PROFILE_REVISION']+':src/cmd/compile/internal/'+f],cwd=root,text=True) if os.environ.get('S_PROFILE_REVISION') else (root/('src/cmd/compile/internal/'+f)).read_text() for f in ['mir/program.s','mir/program_enum.s','ssa/program.s','codegen/amd64_program.s'])
funcs={m.group(1):m.group(0) for m in re.finditer(r'^func (\w+)\([^\n]*(?:\n(?!func |struct |package |extern ).*)*',texts,re.M)}
structs='\n'.join(m.group(0) for m in re.finditer(r'^struct \w+ \{[^}]*\}',texts,re.M))
roots=['mir_program_function_error'] if mode in ['validate','operands'] else ['mir_program_value_type','mir_program_value_use_error','mir_program_dominance_matrix']
needed=set();pending=list(roots)
while pending:
 n=pending.pop()
 if n in needed: continue
 needed.add(n);pending.extend(x for x in re.findall(r'\b(\w+)\s*\(',funcs[n]) if x in funcs and x not in needed)
body=f'''func main() int {{
 blocks := mir_program_block[](); i := 0
 for i < {size} {{
 value_id := i+1
 ins := mir_program_instruction {{ op: "const_int", result_ids: [value_id], result_types: ["int"], integer_value: 42 }}
 successors := int[](); term := "return"; returns := [value_id]
 if i+1 < {size} {{ successors.push(7+(i+1)*3); term = "jump"; returns = int[]() }}
 blocks.push(mir_program_block {{ id: 7+i*3, instructions: [ins], successors: successors, terminator: term, return_values: returns }})
 i = i+1
 }}
 f := mir_program_function {{ symbol: "main", blocks: blocks, result_types: ["int"] }}
'''
if mode in ['validate','operands']: body+='if mir_program_function_error(f, [f]) != "" { return 1 }\n'
else: body+=f'''matrix := mir_program_dominance_matrix(f)
 i = 0
 for i < {size} {{
 if mir_program_value_type(f, i+1, {size}) != "int" {{ return 2 }}
 if mir_program_value_use_error(f, matrix, i+1, {size-1}, 1) != "" {{ return 3 }}
 i = i+1
 }}
'''
if mode=='operands':
 body=body.replace('successors := int[]();', 'copy_id := 10000+i; copied := mir_program_instruction { op: "copy", result_ids: [copy_id], result_types: ["int"], operands: [value_id] }; successors := int[]();').replace('returns := [value_id]', 'returns := [copy_id]').replace('instructions: [ins]', 'instructions: [ins, copied]')
body+='return 42\n}\n'
(out/'driver.s').write_text('package main\n'+structs+'\n'+'\n'.join(v for n,v in funcs.items() if n in needed)+'\n'+body)
commands=[]
def run(cmd):
 commands.append(list(map(str,cmd)));return subprocess.run(commands[-1],check=True,capture_output=True,timeout=90,cwd=root)
run([root/'bin/s_seed','--compile-native-unit',out/'driver.ir',out/'driver.s'])
run([root/'bin/s_seed','--emit-standalone-amd64-asm',out/'driver.ir',out/'driver.S'])
asm=(out/'driver.S').read_text(); targets=['mir_program_dominance_matrix','ssa_dominance_matrix','mir_program_value_use_error','mir_program_value_type','mir_program_function_error_with_globals']
for idx,n in enumerate(targets,1):
 pattern=r'(^s_fn_'+n+r':\n)(.*?)(^\.size s_fn_'+n+r',.*$)'
 def instrument(m):
  start=f'    mov profile_depth(%rip), %rax\n    lea profile_stack(%rip), %r11\n    movq ${idx}, (%r11,%rax,8)\n    incq profile_depth(%rip)\n    incq profile_calls+{idx*8}(%rip)\n'
  return m[1]+start+m[2].replace('    ret\n','    decq profile_depth(%rip)\n    ret\n')+m[3]
 asm=re.sub(pattern,instrument,asm,flags=re.M|re.S)
(out/'instrumented.S').write_text(asm)
runtime=(root/'src/runtime/selfhost_linux_amd64.S').read_text()
# Slots: 0..5 exclusive snapshot-array elements, 6..11 appended elements, 12..17 calls, 18 total copy-impl calls.
account='    mov profile_depth(%rip), %rax\n    lea profile_stack(%rip), %r11\n    mov -8(%r11,%rax,8), %rax\n'
runtime=runtime.replace('.Lrecord_copy_array:\n','.Lrecord_copy_array:\n'+account+'    lea profile_counts(%rip), %r11\n    mov 8(%rdi), %rax\n    add %rax, (%r11)\n',1) if False else runtime
# Need two scratch regs and length without clobbering original argument.
runtime=runtime.replace('.Lrecord_copy_array:\n','.Lrecord_copy_array:\n'+account+'    lea profile_counts(%rip), %r11\n    mov 8(%rdi), %rcx\n    add %rcx, (%r11,%rax,8)\n',1)
runtime=runtime.replace('.Larray_append_allocate:\n','.Larray_append_allocate:\n'+account+'    lea profile_appends(%rip), %r11\n    add %r13, (%r11,%rax,8)\n',1)
runtime=runtime.replace('s_value_copy_impl:\n','s_value_copy_impl:\n    incq profile_impl_calls(%rip)\n',1)
runtime=runtime.replace('    call s_main\n','    call s_main\n    push %rax\n    mov $1,%edi\n    lea profile_counts(%rip),%rsi\n    mov $152,%edx\n    mov $1,%eax\n    syscall\n    pop %rax\n',1)
runtime+='\n.section .bss\n.balign 8\n.global profile_depth,profile_stack,profile_counts,profile_appends,profile_calls\nprofile_depth: .quad 1\nprofile_stack: .zero 8192\nprofile_counts: .zero 48\nprofile_appends: .zero 48\nprofile_calls: .zero 48\nprofile_impl_calls: .quad 0\n'
# Initialized depth must be in .data, not bss.
runtime=runtime.replace('profile_depth: .quad 1','profile_depth: .quad 0')
# Give stack one base slot at startup (runtime before s_main).
runtime=runtime.replace('    call s_main\n','    movq $1, profile_depth(%rip)\n    call s_main\n',1)
(out/'runtime.S').write_text(runtime)
for n in ['runtime','instrumented']:run(['as','--64','-o',out/(n+'.o'),out/(n+'.S')])
run(['ld','-static','--gc-sections','-T',root/'src/runtime/linker/nostdlib.ld','-o',out/'driver',out/'runtime.o',out/'instrumented.o'])
def limits():
 resource.setrlimit(resource.RLIMIT_AS,(768*1024**2,)*2);resource.setrlimit(resource.RLIMIT_CPU,(110,)*2);resource.setrlimit(resource.RLIMIT_CORE,(0,0))
begin=time.monotonic(); status='exited'
cmd=['/usr/bin/time','-v','-o',str(out/'runtime.time'),str(out/'driver')];commands.append(cmd)
try: result=subprocess.run(cmd,capture_output=True,timeout=115,preexec_fn=limits)
except subprocess.TimeoutExpired as e:
 result=e;status='timeout'
metrics={'blocks':size,'mode':mode,'status':status,'wall_seconds':time.monotonic()-begin,'exit':getattr(result,'returncode',None),'commands':commands,'profile_names':['driver']+targets}
if len(result.stdout or b'')==152:
 data=struct.unpack('<19Q',result.stdout);metrics.update(snapshotted_elements=list(data[:6]),copied_elements=list(data[6:12]),calls=list(data[12:18]),s_value_copy_impl_calls=data[18])
metrics['time_v']=(out/'runtime.time').read_text();(out/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n');print(json.dumps(metrics,indent=2));assert metrics['exit']==42,metrics

if mode == 'operands':
 assert metrics['snapshotted_elements'][5] < size**2*100, 'per-operand validation snapshots exceed quadratic cost bound'
