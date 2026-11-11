"""PostgreSQL protocol unit fixtures; no live server or authentication claims."""
from database_test_support import NativeDatabaseCase, ROOT


class PostgreSQLProtocolTests(NativeDatabaseCase):
    sources = [ROOT / 'src/std/database/wire.s', ROOT / 'src/std/postgresql/protocol.s']

    def test_framing_startup_extended_query_and_bound_parameters(self):
        self.execute('postgresql_messages.s', self.sources)

    def test_nonlocalized_severity_is_order_independent_and_errors_are_validated(self):
        self.execute('postgresql_security.s', self.sources)

    def test_full_uint16_parameter_limits(self):
        self.execute('postgresql_limits.s', self.sources)

    def test_rows_errors_authentication_and_transaction_status(self):
        self.execute('postgresql_results.s', self.sources)


if __name__ == '__main__':
    import unittest
    unittest.main()
