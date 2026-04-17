from __future__ import annotations

from pathlib import Path
import unittest

from compiler.ast import dump_source_file
from compiler.lexer import Lexer, dump_tokens
from compiler.parser import parse_source


ROOT = Path(__file__).resolve().parent
FIXTURES = ROOT / "fixtures"


class GoldenTests(unittest.TestCase):
    def test_lexer_golden(self)  None:
        source = (FIXTURES / "sample.s").read_text()
        expected = (FIXTURES / "sample.tokens").read_text().strip()
        actual = dump_tokens(Lexer(source).tokenize()).strip()
        self.assertEqual(expected, actual)

    def test_parser_golden(self)  None:
        source = (FIXTURES / "sample.s").read_text()
        expected = (FIXTURES / "sample.ast").read_text().strip()
        actual = dump_source_file(parse_source(source)).strip()
        self.assertEqual(expected, actual)

    def test_match_parser_golden(self)  None:
        source = (FIXTURES / "match_sample.s").read_text()
        expected = (FIXTURES / "match_sample.ast").read_text().strip()
        actual = dump_source_file(parse_source(source)).strip()
        self.assertEqual(expected, actual)

    def test_binary_parser_golden(self)  None:
        source = (FIXTURES / "binary_sample.s").read_text()
        expected = (FIXTURES / "binary_sample.ast").read_text().strip()
        actual = dump_source_file(parse_source(source)).strip()
        self.assertEqual(expected, actual)

    def test_control_flow_parser_golden(self)  None:
        source = (FIXTURES / "control_flow_sample.s").read_text()
        expected = (FIXTURES / "control_flow_sample.ast").read_text().strip()
        actual = dump_source_file(parse_source(source)).strip()
        self.assertEqual(expected, actual)

    def test_member_method_parser_golden(self)  None:
        source = (FIXTURES / "member_method_sample.s").read_text()
        expected = (FIXTURES / "member_method_sample.ast").read_text().strip()
        actual = dump_source_file(parse_source(source)).strip()
        self.assertEqual(expected, actual)

    def test_cfor_parser_golden(self)  None:
        source = (FIXTURES / "cfor_sample.s").read_text()
        expected = (FIXTURES / "cfor_sample.ast").read_text().strip()
        actual = dump_source_file(parse_source(source)).strip()
        self.assertEqual(expected, actual)


if __name__ == "__main__":
    unittest.main()
