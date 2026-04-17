#!/usr/bin/env python3
"""
Convert camelCase identifiers to snake_case in .s files (only tokens starting with a lowercase letter
and containing an uppercase letter). Skips strings and comments. Creates backups under
.migrations/snake_case_backup/ and writes a mapping file .migrations/snake_case_map.txt.

Usage: python3 misc/scripts/convert_camel_to_snake.py --apply
"""
import os, re, sys, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKUP_DIR = ROOT / ".migrations" / "snake_case_backup"
MAP_FILE = ROOT / ".migrations" / "snake_case_map.txt"

CAMEL_RE = re.compile(r"\b([a-z][A-Za-z0-9]*[A-Z][A-Za-z0-9_]*)\b")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

# conservative keyword list to avoid renaming language keywords or builtin types
KEYWORDS = {
    'package','use','func','int','return','for','if','else','while','break','continue',
    'struct','enum','var','const','true','false','println','import','as'
}


def to_snake(name: str) -> str:
    # insert underscore before each uppercase letter (except at start), then lower
    s = re.sub(r'(.)([A-Z][a-z0-9])', r"\1_\2", name)
    s = re.sub(r'([a-z0-9])([A-Z])', r"\1_\2", s)
    return s.lower()


def find_s_files(root: Path):
    for p in root.rglob('*.s'):
        # skip build artifacts in hidden folders
        if '.git' in p.parts or '.migrations' in p.parts:
            continue
        yield p


def extract_candidates(path: Path):
    candidates = set()
    data = path.read_text(encoding='utf-8')
    i = 0
    n = len(data)
    state = 'code'
    while i < n:
        ch = data[i]
        # detect comments
        if state == 'code' and data.startswith('//', i):
            state = 'line_comment'
            i += 2
            continue
        if state == 'code' and data.startswith('/*', i):
            state = 'block_comment'
            i += 2
            continue
        if state == 'code' and ch == '"':
            state = 'double_quote'
            i += 1
            continue
        if state == 'code' and ch == "'":
            state = 'single_quote'
            i += 1
            continue
        if state == 'line_comment':
            if ch == '\n':
                state = 'code'
            i += 1
            continue
        if state == 'block_comment':
            if data.startswith('*/', i):
                state = 'code'
                i += 2
            else:
                i += 1
            continue
        if state == 'double_quote':
            if ch == '\\':
                i += 2
            elif ch == '"':
                state = 'code'
                i += 1
            else:
                i += 1
            continue
        if state == 'single_quote':
            if ch == '\\':
                i += 2
            elif ch == "'":
                state = 'code'
                i += 1
            else:
                i += 1
            continue
        # in code: detect identifiers
        if state == 'code' and (ch.isalpha() or ch == '_'):
            j = i+1
            while j < n and (data[j].isalnum() or data[j] == '_'):
                j += 1
            token = data[i:j]
            if token not in KEYWORDS and CAMEL_RE.match(token):
                candidates.add(token)
            i = j
            continue
        i += 1
    return candidates


def apply_replacements(path: Path, mapping: dict):
    data = path.read_text(encoding='utf-8')
    out = []
    i = 0
    n = len(data)
    state = 'code'
    while i < n:
        ch = data[i]
        if state == 'code' and data.startswith('//', i):
            state = 'line_comment'
            out.append('//')
            i += 2
            continue
        if state == 'code' and data.startswith('/*', i):
            state = 'block_comment'
            out.append('/*')
            i += 2
            continue
        if state == 'code' and ch == '"':
            state = 'double_quote'
            out.append('"')
            i += 1
            continue
        if state == 'code' and ch == "'":
            state = 'single_quote'
            out.append("'")
            i += 1
            continue
        if state == 'line_comment':
            out.append(ch)
            if ch == '\n':
                state = 'code'
            i += 1
            continue
        if state == 'block_comment':
            if data.startswith('*/', i):
                state = 'code'
                out.append('*/')
                i += 2
            else:
                out.append(ch)
                i += 1
            continue
        if state == 'double_quote':
            out.append(ch)
            if ch == '\\':
                if i+1 < n:
                    out.append(data[i+1]); i += 2; continue
            elif ch == '"':
                state = 'code'
            i += 1
            continue
        if state == 'single_quote':
            out.append(ch)
            if ch == '\\':
                if i+1 < n:
                    out.append(data[i+1]); i += 2; continue
            elif ch == "'":
                state = 'code'
            i += 1
            continue
        # in code: identifiers
        if state == 'code' and (ch.isalpha() or ch == '_'):
            j = i+1
            while j < n and (data[j].isalnum() or data[j] == '_'):
                j += 1
            token = data[i:j]
            if token in mapping:
                out.append(mapping[token])
            else:
                out.append(token)
            i = j
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def main(apply_changes=False):
    s_files = list(find_s_files(ROOT))
    print(f'Found {len(s_files)} .s files')
    all_candidates = set()
    for p in s_files:
        try:
            c = extract_candidates(p)
            if c:
                print(f'  {p.relative_to(ROOT)}: {len(c)} candidates')
            all_candidates.update(c)
        except Exception as e:
            print('skip', p, 'err', e)
    print(f'Total candidate identifiers: {len(all_candidates)}')
    mapping = {}
    for ident in sorted(all_candidates):
        new = to_snake(ident)
        if new != ident:
            mapping[ident] = new
    if not mapping:
        print('No identifiers to rename. Exiting.')
        return
    print('Planned renames:')
    for k,v in mapping.items():
        print(f'  {k} -> {v}')

    if not apply_changes:
        print('\nRun with --apply to actually modify files')
        return

    # make backups
    if BACKUP_DIR.exists():
        print('Backup dir exists; skipping backup creation')
    else:
        for p in s_files:
            dest = BACKUP_DIR / p.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, dest)
        print(f'Backed up originals to {BACKUP_DIR}')

    # apply replacements
    changed = []
    for p in s_files:
        newtext = apply_replacements(p, mapping)
        if newtext != p.read_text(encoding='utf-8'):
            p.write_text(newtext, encoding='utf-8')
            changed.append(p)
    print(f'Modified {len(changed)} files')
    MAP_FILE.parent.mkdir(parents=True, exist_ok=True)
    with MAP_FILE.open('w', encoding='utf-8') as f:
        for k,v in mapping.items():
            f.write(f'{k} {v}\n')
    print(f'Wrote mapping to {MAP_FILE}')


if __name__ == '__main__':
    apply_changes = '--apply' in sys.argv
    main(apply_changes)
