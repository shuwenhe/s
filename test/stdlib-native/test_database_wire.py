"""Bounds-checked wire primitives execute without network or database mocks."""
from database_test_support import NativeDatabaseCase, ROOT


class DatabaseWireTests(NativeDatabaseCase):
    def test_endianness_uint64_truncation_and_sticky_errors(self):
        self.execute('database_wire.s', [ROOT / 'src/std/database/wire.s'])


if __name__ == '__main__':
    import unittest
    unittest.main()
