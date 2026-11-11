"""Common values, precision, rows, and resource state execute as native S."""
from database_test_support import NativeDatabaseCase


class DatabaseTypesTests(NativeDatabaseCase):
    def test_null_precision_strict_conversion_and_execution_metadata(self):
        self.execute('database_types.s')

    def test_rows_distinguish_null_exhaustion_bounds_and_close(self):
        self.execute('database_rows.s')

    def test_busy_children_and_terminal_transaction_states(self):
        self.execute('database_lifecycle.s')


if __name__ == '__main__':
    import unittest
    unittest.main()
