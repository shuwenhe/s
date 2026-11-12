from database_test_support import NativeDatabaseCase, ROOT
class MySQLValuesTests(NativeDatabaseCase):
    def test_binary_signed_unsigned_null_bitmap_datetime_blob_and_decimal(self):
        self.execute('mysql_values.s',[ROOT/'src/std/database/wire.s',*[ROOT/f'src/std/mysql/{name}.s' for name in ('protocol','values','binary')]])
if __name__=='__main__':
    import unittest
    unittest.main()
