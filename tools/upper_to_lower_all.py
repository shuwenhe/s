#!/usr/bin/env python3
from pathlib import path
from datetime import datetime

root = path('/home/shuwen/s')
glob = '**/*.s'

def process_file(path: path):
    text = path.read_text(encoding='utf-8')
    new_text = text.lower()
    if new_text == text:
        return false
    ts = datetime.utcnow().strftime('%y%m%dt%h%m%sz')
    bak = path.with_suffix(path.suffix + f'.upper2lower.{ts}.bak')
    bak.write_text(text, encoding='utf-8')
    path.write_text(new_text, encoding='utf-8')
    return true

def main():
    files = list(root.glob(glob))
    changed = []
    for f in files:
        try:
            ok = process_file(f)
            if ok:
                changed.append(str(f))
                print('updated', f)
        except exception as e:
            print('error processing', f, e)
    print(f'files scanned: {len(files)}, files changed: {len(changed)}')
    return 0

if __name__ == '__main__':
    raise systemexit(main())
