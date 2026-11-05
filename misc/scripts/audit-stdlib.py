#!/usr/bin/env python3
"""Inventory tracked library APIs; source presence is never an execution claim."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    files = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z', 'src'], text=True).split('\0')
    # Include newly implemented public modules before their first commit.
    files = sorted(set(files) | {str(p.relative_to(ROOT)) for p in (ROOT / 'src/std').glob('*.s')})
    packages = {}
    for name in files:
        path = Path(name)
        if path.suffix != '.s' or len(path.parts) < 3 or path.parts[1] in ('cmd', 'compiler', '_seed_probe'):
            continue
        text = (ROOT / path).read_text(errors='replace')
        match = re.search(r'^\s*package\s+([^\s;]+)', text, re.M)
        package = match[1] if match else '(no package)'
        row = packages.setdefault(package, {'files': [], 'placeholder_files': [], 'apis': [], 'intrinsics': []})
        functions = re.findall(r'^func\s+([^\n{]+)', text, re.M)
        names = re.findall(r'^func\s+(\w+)\s*\(', text, re.M)
        placeholder = bool(names) and all(n.endswith(('_unit_name', '_unit_ready')) for n in names)
        row['files'].append(name)
        if placeholder:
            row['placeholder_files'].append(name)
        else:
            row['apis'].extend({'file': name, 'signature': 'func ' + f.strip()} for f in functions)
        row['intrinsics'].extend({'file': name, 'declaration': line.strip()} for line in text.splitlines()
                                 if line.strip().startswith('extern "intrinsic"'))
    report = {'revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
              'method': 'All tracked S sources outside compiler-command trees plus new src/std modules; placeholder-shaped means every named top-level function is *_unit_name or *_unit_ready. No runtime support or test PASS inferred.',
              'source_files': sum(len(p['files']) for p in packages.values()),
              'placeholder_shaped_files': sum(len(p['placeholder_files']) for p in packages.values()),
              'packages': packages}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'packages'}))


if __name__ == '__main__':
    main()
