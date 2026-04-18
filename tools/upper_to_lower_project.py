#!/usr/bin/env python3
from pathlib import path
from datetime import datetime
import sys

root = path('/home/shuwen/s')

binary_threshold = 0.30

def is_binary(data: bytes) -> bool:
    if not data:
        return false
    # if null bytes present, treat as binary
    if b'\x00' in data:
        return true
    # heuristic: proportion of non-text bytes
    text_chars = bytearray({7,8,9,10,12,13,27} | set(range(0x20,0x100)))
    non_text = sum(1 for b in data if b not in text_chars)
    return (non_text / len(data)) > binary_threshold


def process_file(path: path):
    try:
        raw = path.read_bytes()
    except exception as e:
        return false, f'read_error: {e}'
    if is_binary(raw[:4096]):
        return false, 'binary'
    try:
        text = raw.decode('utf-8')
    except exception:
        try:
            text = raw.decode('latin-1')
        except exception as e:
            return false, f'decode_error: {e}'
    new_text = text.lower()
    if new_text == text:
        return false, 'unchanged'
    ts = datetime.utcnow().strftime('%y%m%dt%h%m%sz')
    bak = path.with_suffix(path.suffix + f'.upper2lower_all.{ts}.bak')
    bak.write_text(text, encoding='utf-8')
    path.write_text(new_text, encoding='utf-8')
    return true, 'updated'


def main():
    files = [p for p in root.rglob('*') if p.is_file()]
    changed = []
    skipped = []
    for f in files:
        ok, reason = process_file(f)
        if ok:
            changed.append((str(f), reason))
            print('updated', f)
        else:
            skipped.append((str(f), reason))
    print(f'files scanned: {len(files)}, updated: {len(changed)}, skipped: {len(skipped)}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
