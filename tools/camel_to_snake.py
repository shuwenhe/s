#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path('/home/shuwen/s')
GLOB = '**/*.s'
BACKUP_EXT = '.camel2snake.bak'

# identifier pattern: has at least one uppercase letter
ident_re = re.compile(r"\b[A-Za-z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b")

def to_snake(name):
    s1 = re.sub('(.)([A-Z][a-z]+)', r"\1_\2", name)
    s2 = re.sub('([a-z0-9])([A-Z])', r"\1_\2", s1)
    return s2.lower()

def split_segments(text):
    # split into segments: tuples (kind, content)
    # kind: 'code', 'line_comment', 'block_comment', 'string_double', 'string_single'
    i = 0
    n = len(text)
    segments = []
    while i < n:
        ch = text[i]
        if text.startswith('//', i):
            j = text.find('\n', i)
            if j == -1:
                segments.append(('line_comment', text[i:]))
                break
            else:
                segments.append(('line_comment', text[i:j+1]))
                i = j+1
                continue
        if text.startswith('/*', i):
            j = text.find('*/', i+2)
            if j == -1:
                segments.append(('block_comment', text[i:]))
                break
            else:
                segments.append(('block_comment', text[i:j+2]))
                i = j+2
                continue
        if ch == '"':
            # double quoted string
            j = i+1
            escaped = False
            while j < n:
                if text[j] == '\\' and not escaped:
                    escaped = True
                    j += 1
                    continue
                if text[j] == '"' and not escaped:
                    j += 1
                    break
                escaped = False
                j += 1
            segments.append(('string_double', text[i:j]))
            i = j
            continue
        if ch == "'":
            j = i+1
            escaped = False
            while j < n:
                if text[j] == '\\' and not escaped:
                    escaped = True
                    j += 1
                    continue
                if text[j] == "'" and not escaped:
                    j += 1
                    break
                escaped = False
                j += 1
            segments.append(('string_single', text[i:j]))
            i = j
            continue
        # code char
        j = i
        while j < n and not text.startswith('//', j) and not text.startswith('/*', j) and text[j] not in ('"', "'"):
            j += 1
        segments.append(('code', text[i:j]))
        i = j
    return segments


def process_file(path: Path):
    text = path.read_text(encoding='utf-8')
    segments = split_segments(text)
    changed = False
    replacements = {}

    new_segments = []
    for kind, seg in segments:
        if kind != 'code':
            new_segments.append(seg)
            continue
        # replace identifiers in code segments
        def repl(m):
            name = m.group(0)
            new = to_snake(name)
            if new == name:
                return name
            replacements[name] = new
            return new
        new_seg = ident_re.sub(repl, seg)
        if new_seg != seg:
            changed = True
        new_segments.append(new_seg)

    if not changed:
        return False, {}

    # create backup
    bak = path.with_suffix(path.suffix + BACKUP_EXT)
    bak.write_text(text, encoding='utf-8')
    # write new content
    new_text = ''.join(new_segments)
    path.write_text(new_text, encoding='utf-8')
    return True, replacements


def main():
    files = list(ROOT.glob(GLOB))
    total_changed = 0
    summary = {}
    for f in files:
        changed, reps = process_file(f)
        if changed:
            total_changed += 1
            summary[str(f)] = reps
            print(f'Updated {f}: {len(reps)} replacements')
    print(f'Files scanned: {len(files)}, files changed: {total_changed}')
    if total_changed == 0:
        return 0
    # show brief mapping
    for f, reps in summary.items():
        print(f'-- {f}')
        for k, v in reps.items():
            print(f'    {k} -> {v}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
