from __future__ import annotations 
from typing import Any

import unittest 

from compiler .mir import dropstmt ,movestmt ,lower_block 
from compiler .ownership import make_plan 
from compiler .parser import parse_source 
from compiler .prelude import prelude 
from compiler .typesys import parse_type 


class mirtests (unittest .testcase ):
    def test_if_lowering_emits_block_param_join (self )->None :
        source ="""
package demo.mir

pub func choose(flag: bool) int32 {
    if flag {
        1
    } else {
        2
    }
}
"""
        parsed =parse_source (source )
        func =parsed .items [0 ]
        graph =lower_block (func .body ,[param .name for param in func .sig .params ])
        join_blocks =[block for block in graph .blocks .values ()if block .params ]
        self .asserttrue (join_blocks )
        arg_edges =[edge for block in graph .blocks .values ()for edge in block .terminator .edges if edge .args ]
        self .asserttrue (
        Any (edge .args for edge in arg_edges ),
        arg_edges ,
        )
        self .asserttrue (all (edge .id for edge in arg_edges ))

    def test_locals_are_versioned (self )->None :
        source ="""
package demo.mir

pub func shadow(x: int32) int32 {
    let x = 1
    x
}
"""
        parsed =parse_source (source )
        func =parsed .items [0 ]
        graph =lower_block (func .body ,[param .name for param in func .sig .params ])
        versions =[slot .version for slot in graph .locals .values ()if slot .name =="x"]
        self .assertgreaterequal (len (versions ),2 )
        self .assertin (0 ,versions )
        self .assertin (1 ,versions )

    def test_ownership_plan_drives_move_and_drop (self )->None :
        source ="""
package demo.mir

pub func take(text: string) string {
    let other = text
    other
}
"""
        parsed =parse_source (source )
        func =parsed .items [0 ]
        graph =lower_block (
        func .body ,
        [param .name for param in func .sig .params ],
        {"text":parse_type ("string"),"other":parse_type ("string")},
        make_plan ({"text":parse_type ("string"),"other":parse_type ("string")}),
        )
        moves =[stmt for block in graph .blocks .values ()for stmt in block .statements if isinstance (stmt ,movestmt )]
        drops =[stmt for block in graph .blocks .values ()for stmt in block .statements if isinstance (stmt ,dropstmt )]
        self .asserttrue (moves )
        self .asserttrue (drops )

    def test_prelude_decl_has_traits_and_index (self )->None :
        self .assertequal (prelude .name ,"std.prelude")
        self .assertin ("len",prelude .traits )
        self .assertin ("clone",prelude .types ["string"].traits )
        self .assertequal (prelude .types ["vec"].index_result_kind ,"first_type_arg")
        self .assertin ("len",prelude .types ["string"].default_impls )
        self .assertequal (prelude .types ["fileinfo"].fields ["size"].visibility ,"pub")
        self .assertfalse (prelude .types ["fileinfo"].fields ["size"].writable )
        self .assertfalse (prelude .types ["fileinfo"].fields ["hidden"].readable )
        self .assertequal (len (prelude .types ["vec"].methods ["push"]),1 )
        self .assertequal (prelude .types ["vec"].methods ["push"][0 ].receiver_policy ,"addressable")