#!/usr/bin/env python3
"""Keep canonical and seed raw Linux OS routines byte-identical by construction."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    assembly = (ROOT / 'src/runtime/native_os_amd64.S').read_text()
    chunks = [json.dumps(assembly[i:i + 256], ensure_ascii=True) for i in range(0, len(assembly), 256)]
    function = 'func amd64_os_runtime() string {\n    return ' + '\n        + '.join(chunks) + '\n}\n'
    targets = [
        ('src/cmd/compile/internal/codegen/amd64_program.s', '// BEGIN GENERATED NATIVE OS', '// END GENERATED NATIVE OS', function),
        ('src/runtime/selfhost_linux_amd64.S', '# BEGIN GENERATED NATIVE OS', '# END GENERATED NATIVE OS', assembly),
    ]
    for relative, begin, end, content in targets:
        path = ROOT / relative
        source = path.read_text()
        generated = begin + '\n' + content + end
        if begin in source:
            start = source.index(begin)
            finish = source.index(end, start) + len(end)
            updated = source[:start] + generated + source[finish:]
        else:
            updated = source.rstrip() + '\n\n' + generated + '\n'
        if args.check:
            if updated != source:
                raise SystemExit('stale generated native OS runtime: ' + relative)
        else:
            path.write_text(updated)


if __name__ == '__main__':
    main()
