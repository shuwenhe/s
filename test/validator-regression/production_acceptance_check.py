#!/usr/bin/env python3
"""Compile unmodified production validator function closures and constructed objects.

Each variant is seed compiled and executed; parsing/build failures abort and never
count as rejection. The baseline defaults to the strict MIR restoration commit.
"""
from pathlib import Path
import argparse, hashlib, json, re, struct, subprocess, time

root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--seed', type=Path, default=root/'bin/s_seed')
p.add_argument('--baseline', default='ec8737231')
p.add_argument('--sizes', nargs='+', type=int, default=[16,64,256,1024])
p.add_argument('--compiler-a', type=Path)
p.add_argument('--compiler-b', type=Path)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
if bool(a.compiler_a) != bool(a.compiler_b):
    p.error('--compiler-a and --compiler-b must be supplied together')
files = ['mir/program.s', 'mir/program_enum.s', 'ssa/program.s', 'codegen/amd64_program.s']

def run(cmd, **kw):
    return subprocess.run(list(map(str,cmd)), check=True, timeout=180, **kw)

def source(variant, roots):
    texts=[]
    for f in files:
        path='src/cmd/compile/internal/'+f
        texts.append(subprocess.check_output(['git','show',a.baseline+':'+path],cwd=root,text=True) if variant=='A' else (root/path).read_text())
    text='\n'.join(texts)
    funcs={m.group(1):m.group(0) for m in re.finditer(r'^func (\w+)\([^\n]*(?:\n(?!func |struct |package |extern ).*)*',text,re.M)}
    structs='\n'.join(m.group(0) for m in re.finditer(r'^struct \w+ \{[^}]*\}',text,re.M))
    needed=set(); pending=list(roots)
    while pending:
        n=pending.pop()
        if n in needed: continue
        needed.add(n)
        pending.extend(x for x in re.findall(r'\b(\w+)\s*\(',funcs[n]) if x in funcs and x not in needed)
    return 'package main\n'+structs+'\n'+'\n'.join(body for name,body in funcs.items() if name in needed)+'\n'

def build(name, text):
    unit=a.output/(name+'.s'); unit.write_text(text)
    ir=unit.with_suffix('.ir'); assembly=unit.with_suffix('.S'); obj=unit.with_suffix('.o'); binary=a.output/name
    run([a.seed,'--compile-native-unit',ir,unit],cwd=root)
    run([a.seed,'--emit-standalone-amd64-asm',ir,assembly],cwd=root)
    run(['as','--64','-o',obj,assembly])
    run(['ld','-static','--gc-sections','-T',root/'src/runtime/linker/nostdlib.ld','-o',binary,a.output/'runtime.o',obj])
    return binary

runtime=(root/'src/runtime/selfhost_linux_amd64.S').read_text()
assert '.Larray_append_allocate:\n' in runtime
runtime=runtime.replace('.Larray_append_allocate:\n','.Larray_append_allocate:\n    add %r13, acceptance_copied(%rip)\n',1)
runtime=runtime.replace('    call s_main\n', '    call s_main\n    push %rax\n    mov $1, %edi\n    lea acceptance_copied(%rip), %rsi\n    mov $8, %edx\n    mov $1, %eax\n    syscall\n    pop %rax\n',1)
runtime+='\n.section .bss\n.balign 8\nacceptance_copied: .quad 0\n'
(a.output/'runtime.S').write_text(runtime)
run(['as','--64','-o',a.output/'runtime.o',a.output/'runtime.S'])
fixture=(root/'test/ssa/p2_verifier_test.s').read_text()
fixture=fixture[fixture.index('func valid_program'):].replace('func main()', 'func original_main()')
fixture+='\n'+(root/'test/validator-regression/production_acceptance.s').read_text()+'\nfunc main() int { return acceptance_main() }\n'
results={}
for variant in ['A','B']:
    text=source(variant,['verify_ssa_program','amd64_validate_program','emit_function_ssa_amd64','mir_program_function_error'])+fixture
    binary=build('acceptance-'+variant,text)
    result=run([binary],capture_output=True)
    (a.output/(variant+'.diagnostics')).write_bytes(result.stderr)
    results[variant]={'exit':result.returncode,'source_sha256':hashlib.sha256(text.encode()).hexdigest(),'diagnostics_sha256':hashlib.sha256(result.stderr).hexdigest()}
assert (a.output/'A.diagnostics').read_bytes()==(a.output/'B.diagnostics').read_bytes(), 'A/B diagnostic or production assembly mismatch'
# Fixed generated chain, sparse block IDs, both production dominance functions.
for variant in ['A','B']:
    for mode,prefix,typ in [('mir','mir_program','mir_program'),('ssa','ssa','function_ssa')]:
        for size in a.sizes:
            body=f"""
func main() int {{
    blocks := {typ}_block[](); i := 0
    for i < {size} {{
        successors := int[]()
        if i + 1 < {size} {{ successors.push(7 + (i + 1) * 3) }}
        blocks.push({typ}_block {{ id: 7 + i * 3, successors: successors }})
        i = i + 1
    }}
    f := {typ}_function {{ blocks: blocks{', entry_block: 7' if mode=='ssa' else ''} }}
    matrix := {prefix}_dominance_matrix(f)
    if len(matrix) != {size} {{ return 1 }}
    d := 0
    for d < {size} {{
        u := 0
        for u < {size} {{
            expected := 0
            if d <= u {{ expected = 1 }}
            if matrix[d][u] != expected {{ return 2 }}
            u = u + 1
        }}
        d = d + 1
    }}
    return 0
}}
"""
            name=f'{variant}-{mode}-{size}'
            binary=build(name,source(variant,[prefix+'_dominance_matrix'])+body)
            begin=time.monotonic(); peak=0; reason=''; proc=subprocess.Popen([str(binary)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            while proc.poll() is None:
                try:
                    status=Path(f'/proc/{proc.pid}/status').read_text()
                    match=re.search(r'^VmRSS:\s+(\d+)',status,re.M)
                    if match: peak=max(peak,int(match.group(1)))
                except FileNotFoundError: pass
                if peak>450*1024: reason='resident memory exceeded 450 MiB'; proc.kill()
                if time.monotonic()-begin>120: reason='timeout 120s'; proc.kill()
                time.sleep(.005)
            stdout,stderr=proc.communicate()
            results[name]={'exit':proc.returncode,'elapsed_seconds':round(time.monotonic()-begin,6),'peak_rss_kib':peak,'limit_reason':reason,'appended_elements_copied':struct.unpack('<Q',stdout)[0] if len(stdout)==8 else None,'source_sha256':hashlib.sha256((a.output/(name+'.s')).read_bytes()).hexdigest()}
            print(name,results[name],flush=True)
if a.compiler_a:
    positive=a.output/'native-positive.s'
    positive.write_text('package main\nfunc add(int x, int y) int { return x + y }\nfunc main() int { return add(20, 22) }\n')
    artifacts=[]
    for variant,compiler in [('A',a.compiler_a),('B',a.compiler_b)]:
        artifact=a.output/f'native-positive-{variant}.sasm'; binary=a.output/f'native-positive-{variant}'
        run([compiler,'--compile-unit',artifact,positive],cwd=root)
        run([compiler,'--emit-bin',artifact,binary],cwd=root)
        executed=subprocess.run([str(binary)],capture_output=True,timeout=30)
        assert executed.returncode==42,(variant,executed.returncode,executed.stderr)
        artifacts.append(artifact.read_bytes())
        results['compiler-'+variant]={'sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'production_assembly_sha256':hashlib.sha256(artifacts[-1]).hexdigest(),'program_exit':executed.returncode}
    assert artifacts[0]==artifacts[1],'full compiler production assembly differs'
(a.output/'results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
for mode in ['mir','ssa']:
    for size in a.sizes:
        before=results[f'A-{mode}-{size}']; after=results[f'B-{mode}-{size}']
        assert before['exit']==after['exit']==0, (mode,size,before,after)
        assert after['appended_elements_copied'] < before['appended_elements_copied'], (mode,size,'expected lower copy cost',before,after)

