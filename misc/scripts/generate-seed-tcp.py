#!/usr/bin/env python3
"""Generate Seed ABI TCP assembly; no C compiler is required by emitted programs."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check',action='store_true')
args=parser.parse_args()
with tempfile.TemporaryDirectory() as directory:
    output=Path(directory)/'tcp.s'
    subprocess.run(['gcc','-S','-O2','-ffreestanding','-fno-builtin','-fno-stack-protector',
                    '-fno-asynchronous-unwind-tables','-fno-pie',
                    str(ROOT/'src/runtime/native_tcp_seed.c'),'-o',str(output)],check=True)
    assembly=re.sub(r'\.L(\w+)',r'.Lseed_tcp_\1',output.read_text())
    assembly='\n'.join(line for line in assembly.splitlines()
                       if not line.startswith(('\t.file','\t.ident')))+'\n'
path=ROOT/'src/runtime/selfhost_linux_amd64.S'
source=path.read_text()
begin,end='# BEGIN GENERATED SEED TCP','# END GENERATED SEED TCP'
generated=begin+'\n'+assembly+end
if begin in source:
    start=source.index(begin);stop=source.index(end,start)+len(end)
    updated=source[:start]+generated+source[stop:]
else:
    updated=source.rstrip()+'\n\n'+generated+'\n'
if args.check:
    if updated!=source:raise SystemExit('stale generated Seed TCP runtime')
else:path.write_text(updated)
