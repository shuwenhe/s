#!/usr/bin/env python3
import re
from pathlib import Path

root = Path('/home/shuwen/s/src/compiler')
pattern_list = re.compile(r'datfield\s*\(\s*default_factory\s*=\s*List\s*\)')
pattern_list2 = re.compile(r'datfield\s*\(\s*default_factory\s*=\s*List\s*,')
pattern_dict = re.compile(r'datfield\s*\(\s*default_factory\s*=\s*Dict\s*\)')
pattern_dict2 = re.compile(r'datfield\s*\(\s*default_factory\s*=\s*Dict\s*,')
pattern_tuple = re.compile(r'datfield\s*\(\s*default_factory\s*=\s*Tuple\s*\)')
pattern_tuple2 = re.compile(r'datfield\s*\(\s*default_factory\s*=\s*Tuple\s*,')

def fix_text(text: str) -> str:
    text = pattern_list.sub('datfield(default_factory=list)', text)
    text = pattern_list2.sub('datfield(default_factory=list,', text)
    text = pattern_dict.sub('datfield(default_factory=dict)', text)
    text = pattern_dict2.sub('datfield(default_factory=dict,', text)
    text = pattern_tuple.sub('datfield(default_factory=tuple)', text)
    text = pattern_tuple2.sub('datfield(default_factory=tuple,', text)
    text = re.sub(r'default_factory\s*=\s*List\b', 'default_factory=list', text)
    text = re.sub(r'default_factory\s*=\s*Dict\b', 'default_factory=dict', text)
    text = re.sub(r'default_factory\s*=\s*Tuple\b', 'default_factory=tuple', text)
    # Fix accidental uses of typing names as constructors, e.g. Tuple ( ... ) -> tuple(...)
    text = re.sub(r'\bTuple\s*\(', 'tuple(', text)
    text = re.sub(r'\bList\s*\(', 'list(', text)
    text = re.sub(r'\bDict\s*\(', 'dict(', text)
    return text

def main():
    changed = 0
    for p in root.rglob('*.py'):
        s = p.read_text()
        new = fix_text(s)
        if new != s:
            bkp = p.with_suffix(p.suffix + '.bak')
            p.write_text(new)
            p.rename(p)  # touch to ensure permissions preserved
            bkp.write_text(s)
            changed += 1
    print(f'Fixed default_factory occurrences in {changed} files')

if __name__ == '__main__':
    main()
