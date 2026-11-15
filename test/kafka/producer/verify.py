#!/usr/bin/env python3
"""Compare official Kafka console-consumer bytes to independent expectations."""
import sys
from pathlib import Path

def line(partition, offset, headers, key, value):
    def nullable(v):
        return b'null' if v is None else v
    return b'\t'.join([f'Partition:{partition}'.encode(), f'Offset:{offset}'.encode(), headers,
                       nullable(key), nullable(value)]) + b'\n'

rows = [
    (b'NO_HEADERS', None, b'hello'),
    (b'tag:a\0b,tag:null,empty:', b'k\0', b'v\0x'),
    (b'NO_HEADERS', b'tombstone', None),
    (b'NO_HEADERS', b'', b''),
    (b'NO_HEADERS', None, b'batch-0'),
    (b'NO_HEADERS', b'batch-key', b'batch-1'),
    (b'NO_HEADERS', None, b'batch-2'),
    (b'NO_HEADERS', None, b'ack-zero'),
    (b'NO_HEADERS', None, b'ack-barrier'),
    (b'NO_HEADERS', b'large', b'L' * 524288),
]
expected = b''.join(line(0, i, *r) for i, r in enumerate(rows))
actual = Path(sys.argv[1]).read_bytes()
assert actual == expected, f'partition 0 content mismatch: {len(actual)} != {len(expected)} bytes'
assert Path(sys.argv[2]).read_bytes() == line(1, 0, b'NO_HEADERS', None, b'partition-one')
print('Official Kafka consumer oracle: exact keys/values/headers/null/empty/binary/partitions/offsets (11 records): PASS')
