#!/usr/bin/env python3
"""Fix lowercased Python literals and typing names in Python source files under src/compiler.

This script tokenizes files to avoid changing strings/comments and replaces NAME tokens
that match known mis-cased identifiers (e.g. 'none' -> 'None', 'optional' -> 'Optional').
Backups are written next to the file with a .fixbak suffix.
"""
import sys
from pathlib import Path
import io
import tokenize

MAPPING = {
    'none': 'None',
    'true': 'True',
    'false': 'False',
    'optional': 'Optional',
    'list': 'List',
    'dict': 'Dict',
    'any': 'Any',
    'tuple': 'Tuple',
    'callable': 'Callable',
    'set': 'Set',
}

ROOT = Path('src/compiler')

def fix_file(path: Path) -> bool:
    try:
        data = path.read_bytes()
    except Exception as e:
        print(f"skip {path}: read error: {e}")
        return False

    try:
        tokens = []
        changed = False
        g = tokenize.tokenize(io.BytesIO(data).readline)
        for toknum, tokval, start, end, line in g:
            if toknum == tokenize.NAME and tokval in MAPPING:
                tokens.append((toknum, MAPPING[tokval]))
                changed = True
            else:
                tokens.append((toknum, tokval))
    except Exception as e:
        print(f"tokenize failed for {path}: {e}")
        return False

    if not changed:
        return False

    try:
        new = tokenize.untokenize(tokens)
        if isinstance(new, (bytes, bytearray)):
            new = new.decode('utf-8')
        # backup
        bak = path.with_suffix(path.suffix + '.fixbak')
        bak.write_bytes(data)
        path.write_text(new, encoding='utf-8')
        print(f'fixed {path}')
        return True
    except Exception as e:
        print(f"write failed for {path}: {e}")
        return False

def main():
    if not ROOT.exists():
        print('src/compiler not found, aborting')
        sys.exit(1)
    count = 0
    for p in ROOT.rglob('*.py'):
        if fix_file(p):
            count += 1
    print(f'fixed {count} files')

if __name__ == '__main__':
    main()
