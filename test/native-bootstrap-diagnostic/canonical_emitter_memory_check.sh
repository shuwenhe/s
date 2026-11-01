#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
compiler=${1:-"$root/bin/s_compiler"}
work=$(mktemp -d /tmp/s-emitter-memory.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo artifacts=$work; fi' EXIT
# Execute the actual emitter with the canonical flat-string runtime. Running it
# only under the seed's rope runtime would hide retained-prefix allocation.
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import re,sys
root,work=map(Path,sys.argv[1:]); functions={}
ssa=(root/'src/cmd/compile/internal/ssa/program.s').read_text()
for path in ['src/cmd/compile/internal/codegen/amd64_program.s','src/cmd/compile/internal/ssa/program.s']:
 text=(root/path).read_text(); positions=list(re.finditer(r'^func (\w+)\(',text,re.M))
 for i,m in enumerate(positions):functions[m[1]]=text[m.start():positions[i+1].start() if i+1<len(positions) else len(text)]
pending=['amd64_emit_string']; selected=set()
while pending:
 name=pending.pop()
 if name in selected or name not in functions:continue
 selected.add(name)
 code=re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',' ',functions[name])
 pending+=re.findall(r'\b(\w+)\s*\(',code)
a=ssa.index('struct function_ssa_value {'); b=ssa.index('\n}',a)+2
source='package compile.internal\nextern "intrinsic" func __host_byte_at(string text, int index) int\nextern "intrinsic" func __host_write_text_file(string path, string text) int\n'+ssa[a:b]+'\n'+''.join(functions[n] for n in sorted(selected))
source+='\nfunc main() int {\n value := function_ssa_value { id: 0, op: "const_string", symbol: "'+'A'*5000+'" }\n text := amd64_emit_string([value], value, 0, 0)\n if __host_write_text_file("'+str(work/'output.sasm')+'", text) != 0 { return 1 }\n return 42\n}\n'
(work/'probe.s').write_text(source)
expected='.pushsection .rodata\n.balign 8\n.Ls_string_0_0:\n.quad 5000\n'+'.byte 65\n'*5000+'.popsection\n  leaq .Ls_string_0_0(%rip), %rax\n  movq %rax, -8(%rbp)\n'
(work/'expected.sasm').write_text(expected)
PY
"$compiler" --compile-unit "$work/probe.sasm" "$work/probe.s"
"$compiler" --emit-bin "$work/probe.sasm" "$work/probe"
status=0
(ulimit -v 65536; timeout 20 "$work/probe") || status=$?
test "$status" -eq 42 || { echo "native emitter exceeded 64 MiB or failed: exit=$status" >&2; exit 1; }
cmp "$work/expected.sasm" "$work/output.sasm"
echo 'canonical native emitter preserves literal assembly within 64 MiB: PASS'
