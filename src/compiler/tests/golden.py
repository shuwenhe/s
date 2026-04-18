from __future__ import annotations 

from pathlib import Path 
import unittest 

from compiler .ast import dump_source_file 
from compiler .lexer import lexer ,dump_tokens 
from compiler .parser import parse_source 


root =path (__file__ ).resolve ().parent 
fixtures =root /"fixtures"


class goldentests (unittest .testcase ):
    def test_lexer_golden (self )->None :
        source =(fixtures /"sample.s").read_text ()
        expected =(fixtures /"sample.tokens").read_text ().strip ()
        actual =dump_tokens (lexer (source ).tokenize ()).strip ()
        self .assertequal (expected ,actual )

    def test_parser_golden (self )->None :
        source =(fixtures /"sample.s").read_text ()
        expected =(fixtures /"sample.ast").read_text ().strip ()
        actual =dump_source_file (parse_source (source )).strip ()
        self .assertequal (expected ,actual )

    def test_match_parser_golden (self )->None :
        source =(fixtures /"match_sample.s").read_text ()
        expected =(fixtures /"match_sample.ast").read_text ().strip ()
        actual =dump_source_file (parse_source (source )).strip ()
        self .assertequal (expected ,actual )

    def test_binary_parser_golden (self )->None :
        source =(fixtures /"binary_sample.s").read_text ()
        expected =(fixtures /"binary_sample.ast").read_text ().strip ()
        actual =dump_source_file (parse_source (source )).strip ()
        self .assertequal (expected ,actual )

    def test_control_flow_parser_golden (self )->None :
        source =(fixtures /"control_flow_sample.s").read_text ()
        expected =(fixtures /"control_flow_sample.ast").read_text ().strip ()
        actual =dump_source_file (parse_source (source )).strip ()
        self .assertequal (expected ,actual )

    def test_member_method_parser_golden (self )->None :
        source =(fixtures /"member_method_sample.s").read_text ()
        expected =(fixtures /"member_method_sample.ast").read_text ().strip ()
        actual =dump_source_file (parse_source (source )).strip ()
        self .assertequal (expected ,actual )

    def test_cfor_parser_golden (self )->None :
        source =(fixtures /"cfor_sample.s").read_text ()
        expected =(fixtures /"cfor_sample.ast").read_text ().strip ()
        actual =dump_source_file (parse_source (source )).strip ()
        self .assertequal (expected ,actual )


if __name__ =="__main__":
    unittest .main ()
