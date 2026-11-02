from pathlib import Path
import re, subprocess, sys, tempfile, atexit, shutil
root=Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
work=Path(tempfile.mkdtemp(prefix='s-type-contract-'))
atexit.register(shutil.rmtree, work)
mir=(root/'src/cmd/compile/internal/mir/program.s').read_text()+'\n'+(root/'src/cmd/compile/internal/mir/program_enum.s').read_text();ssa=(root/'src/cmd/compile/internal/ssa/program.s').read_text()
def function(text,name):
 m=re.search(r'^func '+name+r'\(',text,re.M); n=re.search(r'^func ',text[m.end():],re.M)
 return text[m.start():m.end()+n.start()] if n else text[m.start():]
source='''package probe
extern "intrinsic" func __host_slice(string source, int start, int end) string
struct mir_program_record { string symbol; string[] field_names; string[] field_types }
struct mir_program_enum { string symbol; string[] variants; int[] tags }
struct function_ssa_record { string symbol; string[] field_names; string[] field_types }
'''
for name in ['mir_program_type_supported','mir_program_record_index','mir_program_record_index_unqualified','mir_program_enum_index','mir_program_array_element','mir_program_reference_element']:
 source+=function(mir,name)+'\n'
for name in ['ssa_type_supported','ssa_record_index','ssa_array_element']:
 source+=function(ssa,name)+'\n'
source+='''func main() int {
    record := mir_program_record { symbol: "shapes.Item" }
    records := [record];
    enums := mir_program_enum[]()
    ssa_record := function_ssa_record { symbol: "shapes.Item" }
    ssa_records := [ssa_record];
    if !mir_program_type_supported("shapes.Item[]", records, enums) { return 1 }
    if !ssa_type_supported("&shapes.Item", ssa_records) { return 2 }
    if !ssa_type_supported("&int", ssa_records) { return 7 }
    if !ssa_type_supported("&mutstring", ssa_records) { return 8 }
    if !ssa_type_supported("&bool", ssa_records) { return 9 }
    if mir_program_type_supported("Unknown", records, enums) { return 3 }
    if mir_program_type_supported("Unknown[int]", records, enums) { return 4 }
    if ssa_type_supported("&Unknown", ssa_records) { return 5 }
    if ssa_type_supported("Unknown[]", ssa_records) { return 6 }
    return 42
}
'''
(work/'main.s').write_text(source)
subprocess.run([str(root/'bin/s_seed'),'--compile-native-unit',str(work/'main.ir'),str(work/'main.s')],check=True)
subprocess.run([str(root/'bin/s_seed'),'--emit-standalone-amd64',str(work/'main.ir'),str(work/'main')],check=True,env=__import__('os').environ|{'S_SOURCE_ROOT':str(root)})
status=subprocess.run([str(work/'main')]).returncode
print('type contract status:',status);sys.exit(0 if status==42 else 1)
