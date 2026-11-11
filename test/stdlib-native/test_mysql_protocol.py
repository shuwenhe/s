"""MySQL wire unit fixtures, explicitly not real-server integration tests."""
from database_test_support import NativeDatabaseCase, ROOT


class MySQLProtocolTests(NativeDatabaseCase):
    sources = [ROOT / 'src/std/database/wire.s', ROOT / 'src/std/mysql/protocol.s']

    def test_packet_sequence_limits_lenenc_and_malformed_frames(self):
        self.execute('mysql_packets.s', self.sources)

    def test_v10_handshake_capabilities_scramble_and_truncation(self):
        self.execute('mysql_handshake.s', self.sources)

    def test_length_encoding_signed_minimum_null_bitmap_and_truncation(self):
        self.execute('mysql_boundaries.s', self.sources)

    def test_prepared_binding_metadata_and_auth_switch(self):
        self.execute('mysql_prepared.s', self.sources)

    def test_ok_error_null_rows_and_command_encoding(self):
        self.execute('mysql_results.s', self.sources)


if __name__ == '__main__':
    import unittest
    unittest.main()
