#!/usr/bin/env python3
"""Execute positive and nine negative controls against real production MIR closures."""
from pathlib import Path
import re,subprocess,json,hashlib,argparse
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output;out.mkdir(parents=True,exist_ok=True)
fixture='''
func base() mir_program_function {
 ins := mir_program_instruction { field_names: string[](), op: "const_int", result_ids: [0], result_types: ["int"], operands: int[](), integer_value: 42, symbol: "" }
 b := mir_program_block { successors: int[](), id: 7, instructions: [ins], terminator: "return", return_values: [0] }
 return mir_program_function { symbol: "sample.main", params: mir_program_parameter[](), result_types: ["int"], blocks: [b], external: false }
}
func expect(mir_program_function f, string wanted) int {
 actual := mir_program_function_error(f, [f])
 eprintln(actual)
 if actual != wanted { return 1 }
 return 0
}
func main() int {
 f := base()
 if expect(f, "") != 0 { return 1 }
 b := f.blocks[0]; b.return_values = [99]; f.blocks[0] = b
 if expect(f, "undefined terminator value") != 0 { return 2 }
 f = base(); f.result_types = ["string"];
 if expect(f, "return type: sample.main") != 0 { return 3 }
 f = base(); b = f.blocks[0]; b.successors = [99]; b.terminator = "jump"; b.return_values = int[](); f.blocks[0] = b
 if expect(f, "unknown successor block") != 0 { return 4 }
 f = base(); b = f.blocks[0]; b.instructions = mir_program_instruction[](); b.terminator = "unreachable"; b.return_values = int[](); f.blocks.push(b)
 if expect(f, "invalid or duplicate block") != 0 { return 5 }
 f = base(); b = f.blocks[0]; ins := b.instructions[0]; b.instructions.push(ins); f.blocks[0] = b
 if expect(f, "duplicate value in: sample.main") != 0 { return 6 }
 f = base(); b = f.blocks[0]; ins = b.instructions[0]; ins.op = "mystery"; b.instructions[0] = ins; f.blocks[0] = b
 if expect(f, "unsupported instruction: mystery") != 0 { return 7 }
 f = base(); b = f.blocks[0]; ins = b.instructions[0]; negative_id := -1; ins.result_ids = [negative_id]; b.instructions[0] = ins; f.blocks[0] = b
 if expect(f, "invalid value in: sample.main") != 0 { return 8 }
 f = base(); b = f.blocks[0]; ins = b.instructions[0]; ins.op = "phi"; ins.operands = [0]; b.instructions[0] = ins; f.blocks[0] = b
 if expect(f, "phi position or predecessor count") != 0 { return 9 }
 f = base(); b = f.blocks[0]; ins = b.instructions[0]; first := ins; first.op = "copy"; first.result_ids = [1]; first.operands = [0]; b.instructions = [first, ins]; f.blocks[0] = b
 if expect(f, "undefined value in: sample.main") != 0 { return 10 }
 return 42
}
'''
records=[]
for variant in ['baseline','fixed']:
 text='\n'.join(subprocess.check_output(['git','show','59eb5e5d8:src/cmd/compile/internal/'+p],cwd=root,text=True) if variant=='baseline' else (root/('src/cmd/compile/internal/'+p)).read_text() for p in ['mir/program.s','mir/program_enum.s'])
 funcs={m[1]:m[0] for m in re.finditer(r'^func (\w+)\([^\n]*(?:\n(?!func |struct |package |extern ).*)*',text,re.M)}
 needed=set();pending=['mir_program_function_error']
 while pending:
  n=pending.pop()
  if n in needed:continue
  needed.add(n);pending.extend(x for x in re.findall(r'\b(\w+)\s*\(',funcs[n]) if x in funcs and x not in needed)
 structs='\n'.join(m[0] for m in re.finditer(r'^struct \w+ \{[^}]*\}',text,re.M))
 unit=out/(variant+'.s');unit.write_text('package main\n'+structs+'\n'+'\n'.join(v for k,v in funcs.items() if k in needed)+'\n'+fixture)
 cmds=[[root/'bin/s_seed','--compile-native-unit',unit.with_suffix('.ir'),unit],[root/'bin/s_seed','--emit-standalone-amd64',unit.with_suffix('.ir'),out/variant]]
 for c in cmds:subprocess.run(list(map(str,c)),cwd=root,check=True,timeout=45)
 x=subprocess.run([str(out/variant)],capture_output=True,timeout=15);(out/(variant+'.diagnostics')).write_bytes(x.stderr)
 records.append(dict(variant=variant,exit=x.returncode,commands=[list(map(str,c)) for c in cmds],sha256=hashlib.sha256((out/variant).read_bytes()).hexdigest()));(out/'results.json').write_text(json.dumps(records,indent=2));assert x.returncode==42,(variant,x.returncode,x.stderr)
assert (out/'baseline.diagnostics').read_bytes()==(out/'fixed.diagnostics').read_bytes()
print('MIR positive + 9 strict negative controls, exact baseline/fixed diagnostic parity: PASS')
