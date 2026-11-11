#!/usr/bin/env python3
"""Generate the freestanding Linux extensions embedded in the S compiler."""
from pathlib import Path
import argparse
import subprocess,json,tempfile,re
root=Path(__file__).resolve().parents[2]
d=root/'src/cmd/compile/internal/codegen'
def generate():
 with tempfile.TemporaryDirectory() as t:
  out=Path(t)/'extensions.s'
  subprocess.run(['gcc','-S','-O2','-ffreestanding','-fno-builtin','-fno-stack-protector','-fno-asynchronous-unwind-tables','-fno-pie',str(d/'native_runtime_extensions.c'),'-o',str(out)],check=True)
  asm=re.sub(r'\.L(?!s_native_)([A-Za-z0-9_]+)', r'.Lext_\1', out.read_text())
  # Native compiler output is linked into one assembly translation unit.
  asm='\n'.join(l for l in asm.splitlines() if not l.startswith('\t.file') and not l.startswith('\t.ident') and not l.lstrip().startswith('#'))+'\n'
  names={'__sys_socket':'socket','__sys_close':'close','__sys_connect':'connect','__sys_read_string':'read','__sys_write_string':'write','__host_file_exists':'exists','__host_env_exists':'env_exists','__host_read_binary_file':'read_binary','__host_read_binary_file_range':'read_range','__host_write_binary_file':'write_binary','__host_run_argv_output':'capture'}
  names['__crypto_random']='crypto_random'
  names.update({'__tcp_dial':'tcp_dial','__tcp_listen':'tcp_listen','__tcp_accept':'tcp_accept','__tcp_port':'tcp_port','__tcp_send':'tcp_send','__tcp_receive':'tcp_receive','__tcp_close':'tcp_close'})
  text='package compile.internal\n\n// Generated from native_runtime_extensions.c; see test/native_runtime/extensions_generate.py.\nfunc amd64_native_extension_target(string name) string {\n'
  for name,suffix in names.items():
   target='s_'+suffix if suffix.startswith(('tcp_','crypto_')) else 's_ext_'+suffix
   text+='    if name == '+json.dumps(name)+' { return '+json.dumps(target)+' }\n'
  text+='    return ""\n}\n\nfunc amd64_native_extensions_runtime() string {\n    return ""\n'
  # Seed IR operands have a 1024-byte capacity; bound escaped literals below it.
  for i in range(0,len(asm),250):
   literal=json.dumps(asm[i:i+250])
   assert len(literal.encode()) < 768
   text+='        + '+literal+'\n'
  text+='}\n'
  return text

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='fail on stale output without writing it')
    parser.add_argument('--output', type=Path, default=d/'native_runtime_extensions.s')
    args = parser.parse_args()
    generated = generate()
    if args.check:
        if not args.output.exists() or args.output.read_text() != generated:
            parser.exit(1, 'stale generated native extensions: ' + str(args.output) + '\n')
    else:
        args.output.write_text(generated)


if __name__ == '__main__':
    main()
