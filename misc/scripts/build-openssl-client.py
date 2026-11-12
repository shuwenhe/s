#!/usr/bin/env python3
"""Build a canonical S native object with the explicit OpenSSL runtime dependency.

Requires a C compiler, OpenSSL headers/libraries and Python 3. The database/client
code remains S; the C bridge supplies TLS only. Default freestanding builds stay
unchanged. No shell command substitution or database client library is used.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('sources',nargs='+',type=Path)
parser.add_argument('-o','--output',type=Path,required=True)
args=parser.parse_args()
output=args.output.resolve()
sources=[path.resolve() for path in args.sources]
if output in sources:parser.error('output must not overwrite an input source')
output.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.s-openssl-',dir=output.parent) as directory:
    work=Path(directory)
    # Existing package resolver supplies real source dependencies, without stubs.
    all_sources=[]
    for source in sources:
        closure=work/'sources.txt'
        subprocess.run(['sh',str(ROOT/'src/cmd/dist/source_closure.sh'),str(source),str(closure)],cwd=ROOT,
                       env=os.environ|{'S_SOURCE_ROOT':str(ROOT)},check=True)
        for line in closure.read_text().splitlines():
            path=Path(line)
            if not path.is_absolute():path=ROOT/path
            path=path.resolve()
            if path not in all_sources:all_sources.append(path)
    if output in all_sources:parser.error('output must not overwrite a dependency')
    combined=work/'combined.s'
    combined.write_text('\n'.join(path.read_text() for path in all_sources))
    obj=work/'program.o'
    compiler=Path(os.environ.get('S_TEST_COMPILER',ROOT/'bin/s_compiler')).resolve()
    assembly=work/'program.s'
    subprocess.run([str(compiler),'--emit-amd64',str(combined),str(assembly)],cwd=ROOT,check=True)
    # libc owns process startup here. Initialize the same argument/environment
    # slots that the freestanding _start initializes, before S global initializers.
    text=assembly.read_text()
    setup=''
    if '.Ls_native_envp:' in text:
        setup='  movq %rdi,.Ls_native_argc(%rip)\n  movq %rsi,.Ls_native_argv(%rip)\n  movq %rdx,.Ls_native_envp(%rip)\n'
    assembly.write_text(text+'\n.text\n.globl s_native_initialize_process\n.type s_native_initialize_process,@function\ns_native_initialize_process:\n'+setup+'  ret\n.section .note.GNU-stack,"",@progbits\n')
    subprocess.run([os.environ.get('S_BOOTSTRAP_AS','as'),'--64',str(assembly),'-o',str(obj)],check=True)
    startup=work/'startup.c'
    startup.write_text('''#include <stdint.h>
extern long s_native_entry(void);
extern uintptr_t s_native_gc_stack_top __attribute__((weak));
extern void s_native_initialize_globals(void) __attribute__((weak));
extern void s_native_initialize_process(long,char**,char**);
int main(int argc,char **argv,char **envp) {
    uintptr_t stack_anchor=0;
    s_native_initialize_process(argc,argv,envp);
    if (&s_native_gc_stack_top) s_native_gc_stack_top=(uintptr_t)&stack_anchor;
    if (s_native_initialize_globals) s_native_initialize_globals();
    return (int)s_native_entry();
}
''')
    binary=work/'program'
    subprocess.run([os.environ.get('CC','cc'),'-std=c11','-O2','-Wall','-Wextra','-Werror','-no-pie',
                    str(startup),str(obj),str(ROOT/'src/runtime/native_tls_openssl.c'),'-lssl','-lcrypto',
                    '-o',str(binary)],check=True)
    os.replace(binary,output)
