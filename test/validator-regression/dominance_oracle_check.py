#!/usr/bin/env python3
"""Compare production MIR/SSA matrices to an independent dominator fixed point.

Cases cover disconnected CFGs, diamonds, cycles, sparse IDs and shuffled SSA entry.
The driver retains extracted source, IR, assembly, ELF and command/exit evidence.
"""
from pathlib import Path
import argparse, hashlib, json, random, re, subprocess

root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--baseline', default='59eb5e5d8')
a = p.parse_args(); a.output.mkdir(parents=True, exist_ok=True)
records = []

def oracle(edges, entry):
    reachable = {entry}
    while True:
        following = reachable | {v for u in reachable for v in edges[u]}
        if following == reachable: break
        reachable = following
    all_nodes = set(range(len(edges)))
    dom = [({entry} if v == entry else set(reachable)) if v in reachable else set(all_nodes) for v in all_nodes]
    while True:
        changed = False
        for v in sorted(reachable - {entry}):
            predecessors = [u for u in reachable if v in edges[u]]
            value = set.intersection(*(dom[u] for u in predecessors)) | {v}
            if value != dom[v]: dom[v] = value; changed = True
        if not changed: return [[int(d in dom[u]) for u in all_nodes] for d in all_nodes]

def closure(text, name):
    funcs = {m[1]: m[0] for m in re.finditer(r'^func (\w+)\([^\n]*(?:\n(?!func |struct |package |extern ).*)*', text, re.M)}
    needed = set(); pending = [name]
    while pending:
        n = pending.pop()
        if n in needed: continue
        needed.add(n)
        pending.extend(x for x in re.findall(r'\b(\w+)\s*\(', funcs[n]) if x in funcs and x not in needed)
    return '\n'.join(m[0] for m in re.finditer(r'^struct \w+ \{[^}]*\}', text, re.M)) + '\n' + '\n'.join(v for k,v in funcs.items() if k in needed)

rng = random.Random(77231)
cases = [[]]
for n in [1,2,3,5,8,16]:
    for repeat in range(4):
        cases.append([[v for v in range(n) if rng.random() < .22] for u in range(n)])
cases = cases[1:]
for variant in ['baseline','fixed']:
    for mode,prefix,typ in [('mir','mir_program','mir_program'),('ssa','ssa','function_ssa')]:
        rel = f'src/cmd/compile/internal/{mode}/program.s'
        text = subprocess.check_output(['git','show',a.baseline+':'+rel],cwd=root,text=True) if variant=='baseline' else (root/rel).read_text()
        tests = []
        for idx,edges in enumerate(cases):
            n = len(edges); entry = 0 if mode=='mir' else (idx*7+1)%n
            expected = oracle(edges,entry)
            ids = [7+i*3 for i in range(n)]
            body = [f'func case_{idx}() int {{', f'blocks := {typ}_block[]()']
            for u, successors in enumerate(edges):
                values = '['+', '.join(str(ids[v]) for v in successors)+']' if successors else 'int[]()'
                body.append(f'blocks.push({typ}_block {{ id: {ids[u]}, successors: {values} }})')
            body.append(f'f := {typ}_function {{ blocks: blocks'+(f', entry_block: {ids[entry]}' if mode=='ssa' else '')+' }')
            body.append(f'matrix := {prefix}_dominance_matrix(f)')
            for d,row in enumerate(expected):
                body.append(f'expected_{d} := ['+', '.join(map(str,row))+'];')
                body.append(f'cursor_{d} := 0; for cursor_{d} < {n} {{ if matrix[{d}][cursor_{d}] != expected_{d}[cursor_{d}] {{ return 1 }}; cursor_{d} = cursor_{d}+1 }}'.replace('};','}'))
            tests.append('\n'.join(body)+'\nreturn 0\n}')
        source = 'package main\n'+closure(text,prefix+'_dominance_matrix')+'\n'+'\n'.join(tests)+'\nfunc main() int {\n'+'\n'.join(f'if case_{i}() != 0 {{ return {i+1} }}' for i in range(len(cases)))+'\nreturn 42\n}\n'
        name = variant+'-'+mode; unit = a.output/(name+'.s');unit.write_text(source)
        commands = [[root/'bin/s_seed','--compile-native-unit',unit.with_suffix('.ir'),unit], [root/'bin/s_seed','--emit-standalone-amd64',unit.with_suffix('.ir'),a.output/name]]
        for cmd in commands: subprocess.run(list(map(str,cmd)),cwd=root,check=True,timeout=45)
        executed = subprocess.run([str(a.output/name)],capture_output=True,timeout=20)
        records.append(dict(name=name,cases=len(cases),exit=executed.returncode,commands=[list(map(str,c)) for c in commands],binary_sha256=hashlib.sha256((a.output/name).read_bytes()).hexdigest()))
        (a.output/'results.json').write_text(json.dumps(records,indent=2)+'\n')
        assert executed.returncode==42,(name,executed.returncode,executed.stderr)
print('24 independent oracle CFG cases x MIR/SSA x baseline/fixed: PASS')
