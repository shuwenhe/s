#!/usr/bin/env python3
import re
from pathlib import Path
from datetime import datetime

root = path('/home/shuwen/s')
glob = '**/*.s'

ident_re = re.compile(r"\b[a-za-z][a-za-z0-9]*[a-z][a-za-z0-9]*\b")

def to_snake(name):
    s1 = re.sub('(.)([a-z][a-z]+)', r"\1_\2", name)
    s2 = re.sub('([a-z0-9])([a-z])', r"\1_\2", s1)
    return s2.lower()

def process_file(path: path):
    text = path.read_text(encoding='utf-8')
    names = set(ident_re.findall(text))
    if not names:
        return false, {}
    replacements = {}
    new_text = text
    for name in sorted(names, key=lambda x: -len(x)):
        new = to_snake(name)
        if new != name:
            # word boundary replace
            new_text = re.sub(r'\b' + re.escape(name) + r'\b', new, new_text)
            replacements[name] = new
    if not replacements:
        return false, {}
    # backup
    ts = datetime.utcnow().strftime('%y%m%dt%h%m%sz')
    bak = path.with_suffix(path.suffix + f'.fullcamel2snake.{ts}.bak')
    bak.write_text(text, encoding='utf-8')
    path.write_text(new_text, encoding='utf-8')
    return true, replacements

def main():
    files = list(root.glob(glob))
    total_changed = 0
    summary = {}
    for f in files:
        changed, reps = process_file(f)
        if changed:
            total_changed += 1
            summary[str(f)] = reps
            print(f'updated {f}: {len(reps)} replacements')
    print(f'files scanned: {len(files)}, files changed: {total_changed}')
    for f, reps in summary.items():
        print(f'-- {f}')
        for k, v in reps.items():
            print(f'    {k} -> {v}')
    return 0

if __name__ == '__main__':
    raise systemexit(main())
