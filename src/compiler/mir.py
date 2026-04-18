from __future__ import annotations

from dataclasses import dataclass, field as datfield
from typing import Dict, List, Optional

from compiler.ast import (
    binaryexpr,
    blockexpr,
    borrowexpr,
    callexpr,
    expr,
    exprstmt,
    forexpr,
    ifexpr,
    indexexpr,
    letstmt,
    structliteralexpr,
    switchexpr,
    memberexpr,
    nameexpr,
    returnstmt,
    unaryexpr,
    whileexpr,
)
from compiler.ownership import ownershipdecision, make_decision
from compiler.typesys import type, unknowntype, parse_type


@dataclass (frozen =True )
class localslot :
    id :int 
    name :str 
    kind :str 
    version :int =0 
    ty :type =datfield (default_factory =unknowntype )


@dataclass (frozen =True )
class operand :
    kind :str 
    value :object 


@dataclass (frozen =True )
class assignstmt :
    target :int 
    op :str 
    args :Tuple [object ,...]


@dataclass (frozen =True )
class evalstmt :
    op :str 
    args :Tuple [object ,...]


@dataclass (frozen =True )
class movestmt :
    target :int 
    source :operand 


@dataclass (frozen =True )
class copystmt :
    target :int 
    source :operand 


@dataclass (frozen =True )
class dropstmt :
    slot :int 


@dataclass (frozen =True )
class controledge :
    id :str 
    target :int 
    args :Tuple [operand ,...]=()


@dataclass 
class terminator :
    kind :str 
    edges :List [controledge ]=datfield(default_factory=list)

    @property 
    def targets (self )->List [int ]:
        return [edge .target for edge in self .edges ]

    @property 
    def target_args (self )->List [Tuple [operand ,...]]:
        return [edge .args for edge in self .edges ]


@dataclass 
class basicblock :
    id :int 
    params :List [int ]=datfield(default_factory=list)
    statements :List [object ]=datfield(default_factory=list)
    terminator :terminator =datfield (default_factory =lambda :terminator ("goto",[]))


@dataclass 
class mirgraph :
    blocks :Dict [int ,basicblock ]
    entry :int 
    exit :int 
    locals :Dict [int ,localslot ]


def lower_block (
block :blockexpr ,
param_names :Optional [List [str ]]=None ,
type_env :Optional [Dict [str ,type ]]=None ,
ownership_plan :Optional [Dict [str ,ownershipdecision ]]=None ,
)->mirgraph :
    builder =_mirbuilder (param_names or [],type_env or {},ownership_plan or {})
    entry ,exits =builder .lower_block (block )
    exit_id =builder .new_block ()
    for block_id in exits :
        builder .blocks [block_id ].terminator =terminator ("goto",[builder .edge (exit_id )])
    return mirgraph (builder .blocks ,entry ,exit_id ,builder .locals )


class _mirbuilder :
    def __init__ (
    self ,
    param_names :List [str ],
    type_env :Dict [str ,type ],
    ownership_plan :Dict [str ,ownershipdecision ],
    )->None :
        self .blocks :Dict [int ,basicblock ]={}
        self .locals :Dict [int ,localslot ]={}
        self .name_to_slot :Dict [str ,int ]={}
        self .name_versions :Dict [str ,int ]={}
        self .type_env =type_env 
        self .ownership_plan =ownership_plan 
        self .next_block_id =0 
        self .next_local_id =0 
        self .next_edge_id =0 
        for name in param_names :
            self .bind_name (name ,"param",self .type_env .get (name ,unknowntype ()))

    def new_block (self )->int :
        block_id =self .next_block_id 
        self .next_block_id +=1 
        self .blocks [block_id ]=basicblock (block_id )
        return block_id 

    def new_temp (self )->int :
        slot_id =self .next_local_id 
        self .next_local_id +=1 
        self .locals [slot_id ]=localslot (slot_id ,f"_t{slot_id }","temp",0 ,unknowntype ())
        return slot_id 

    def edge (self ,target :int ,args :Tuple [operand ,...]=(),label :str ="edge")->controledge :
        edge_id =f"{label }:{self .next_edge_id }"
        self .next_edge_id +=1 
        return controledge (edge_id ,target ,args )

    def bind_name (self ,name :str ,kind :str ,ty :Optional [type ]=None )->int :
        if kind =="param"and name in self .name_to_slot :
            return self .name_to_slot [name ]
        version =self .name_versions .get (name ,-1 )+1 
        self .name_versions [name ]=version 
        slot_id =self .next_local_id 
        self .next_local_id +=1 
        self .locals [slot_id ]=localslot (slot_id ,name ,kind ,version ,ty or self .type_env .get (name ,unknowntype ()))
        self .name_to_slot [name ]=slot_id 
        return slot_id 

    def slot_for_name (self ,name :str )->int :
        return self .bind_name (name ,"local",self .type_env .get (name ,unknowntype ()))

    def _decision_for_slot (self ,slot_id :int )->ownershipdecision :
        slot =self .locals [slot_id ]
        if slot .name in self .ownership_plan :
            return self .ownership_plan [slot .name ]
        return make_decision (slot .ty )

    def _consume_stmt (self ,target :int ,value :operand )->object :
        if value .kind =="slot":
            decision =self ._decision_for_slot (value .value )
            if not decision .copyable :
                return movestmt (target ,value )
        return copystmt (target ,value )

    def lower_block (self ,block :blockexpr )->Tuple [int ,List [int ]]:
        entry =self .new_block ()
        current =entry 
        for stmt in block .statements :
            current =self ._lower_stmt (stmt ,current )
        if block .final_expr is None :
            self ._emit_drops (current )
            return entry ,[current ]
        entry ,exits =self ._lower_tail_expr (block .final_expr ,current ,entry )
        for block_id in exits :
            self ._emit_drops (block_id )
        return entry ,exits 

    def _lower_stmt (self ,stmt ,current :int )->int :
        if isinstance (stmt ,letstmt ):
            inferred =parse_type (stmt .type_name )if stmt .type_name else self ._infer_expr_type (stmt .value )
            slot =self .bind_name (stmt .name ,"local",inferred )
            value =self ._lower_expr (stmt .value ,current )
            self .blocks [current ].statements .append (self ._consume_stmt (slot ,value ))
            return current 
        if isinstance (stmt ,exprstmt ):
            self ._lower_expr (stmt .expr ,current )
            return current 
        if isinstance (stmt ,returnstmt ):
            if stmt .value is not None :
                value =self ._lower_expr (stmt .value ,current )
                self .blocks [current ].statements .append (evalstmt ("return",(value ,)))
            else :
                self .blocks [current ].statements .append (evalstmt ("return",(operand ("unit",()),)))
            return current 
        self .blocks [current ].statements .append (evalstmt ("stmt",(stmt ,)))
        return current 

    def _lower_tail_expr (self ,expr :expr ,current :int ,entry :int )->Tuple [int ,List [int ]]:
        if isinstance (expr ,ifexpr ):
            cond =self ._lower_expr (expr .condition ,current )
            then_entry ,then_exits =self .lower_block (expr .then_branch )
            else_entry =self .new_block ()
            else_exits =[else_entry ]
            then_value :operand |None =None 
            else_value :operand |None =None 
            if expr .else_branch is not None :
                if isinstance (expr .else_branch ,blockexpr ):
                    else_entry ,else_exits =self .lower_block (expr .else_branch )
                else :
                    else_value =self ._lower_expr (expr .else_branch ,else_entry )
                    self .blocks [else_entry ].statements .append (evalstmt ("yield",(else_value ,)))
            for block_id in then_exits :
                for stmt in reversed (self .blocks [block_id ].statements ):
                    if isinstance (stmt ,evalstmt )and stmt .op =="yield":
                        then_value =stmt .args [0 ]
                        break 
            for block_id in else_exits :
                for stmt in reversed (self .blocks [block_id ].statements ):
                    if isinstance (stmt ,evalstmt )and stmt .op =="yield":
                        else_value =stmt .args [0 ]
                        break 
            self .blocks [current ].statements .append (evalstmt ("branch_if",(cond ,)))
            join_block =self .new_block ()
            join_param =self .new_temp ()
            self .blocks [join_block ].params .append (join_param )
            self .blocks [current ].terminator =terminator (
            "branch",
            [
            self .edge (then_entry ,label ="if_then"),
            self .edge (else_entry ,label ="if_else"),
            ],
            )
            if then_value is not None and else_value is not None :
                self .locals [join_param ]=localslot (
                join_param ,
                f"_join{join_param }",
                "param",
                0 ,
                self ._operand_type (then_value ),
                )
                for block_ids ,arg ,label in (
                (then_exits ,then_value ,"if_join_then"),
                (else_exits ,else_value ,"if_join_else"),
                ):
                    for exit_id in block_ids :
                        self .blocks [exit_id ].terminator =terminator ("goto",[self .edge (join_block ,(arg ,),label )])
                self .blocks [join_block ].statements .append (evalstmt ("yield",(operand ("slot",join_param ),)))
            else :
                for block_id in then_exits +else_exits :
                    self .blocks [block_id ].terminator =terminator ("goto",[self .edge (join_block ,label ="if_join")])
            return entry ,[join_block ]
        if isinstance (expr ,switchexpr ):
            subject =self ._lower_expr (expr .subject ,current )
            self .blocks [current ].statements .append (evalstmt ("match_subject",(subject ,)))
            exits :List [int ]=[]
            arm_targets :List [int ]=[]
            arm_values :List [operand ]=[]
            for arm in expr .arms :
                arm_block =self .new_block ()
                value =self ._lower_expr (arm .expr ,arm_block )
                self .blocks [arm_block ].statements .append (evalstmt ("match_arm",(arm .pattern ,value )))
                exits .append (arm_block )
                arm_targets .append (arm_block )
                arm_values .append (value )
            join_block =self .new_block ()
            join_param =self .new_temp ()
            self .blocks [join_block ].params .append (join_param )
            self .blocks [current ].terminator =terminator (
            "switch",
            [self .edge (target ,label =f"match_arm_{index }")for index ,target in enumerate (arm_targets )],
            )
            if arm_values :
                self .locals [join_param ]=localslot (
                join_param ,
                f"_join{join_param }",
                "param",
                0 ,
                self ._operand_type (arm_values [0 ]),
                )
                for block_id ,arg in zip (exits ,arm_values ):
                    self .blocks [block_id ].terminator =terminator (
                    "goto",
                    [self .edge (join_block ,(arg ,),f"match_join_{block_id }")],
                    )
                self .blocks [join_block ].statements .append (evalstmt ("yield",(operand ("slot",join_param ),)))
            else :
                for block_id in exits :
                    self .blocks [block_id ].terminator =terminator ("goto",[self .edge (join_block ,label ="match_join")])
            return entry ,[join_block ]
        if isinstance (expr ,whileexpr ):
            cond_slot =self ._lower_expr (expr .condition ,current )
            body_entry ,body_exits =self .lower_block (expr .body )
            after =self .new_block ()
            self .blocks [current ].statements .append (evalstmt ("while_cond",(cond_slot ,)))
            self .blocks [current ].terminator =terminator (
            "branch",
            [
            self .edge (body_entry ,label ="while_body"),
            self .edge (after ,label ="while_exit"),
            ],
            )
            for block_id in body_exits :
                self .blocks [block_id ].terminator =terminator ("goto",[self .edge (current ,label ="while_back")])
            return entry ,[after ]
        if isinstance (expr ,forexpr ):
            iter_slot =self ._lower_expr (expr .iterable ,current )
            iter_var =self .bind_name (expr .name ,"loop",self ._infer_iter_type (iter_slot ))
            body_entry ,body_exits =self .lower_block (expr .body )
            after =self .new_block ()
            self .blocks [current ].statements .append (evalstmt ("for_iter",(iter_var ,iter_slot )))
            self .blocks [current ].terminator =terminator (
            "branch",
            [
            self .edge (body_entry ,label ="for_body"),
            self .edge (after ,label ="for_exit"),
            ],
            )
            for block_id in body_exits :
                self .blocks [block_id ].terminator =terminator ("goto",[self .edge (current ,label ="for_back")])
            return entry ,[after ]
        value =self ._lower_expr (expr ,current )
        self .blocks [current ].statements .append (evalstmt ("yield",(value ,)))
        return entry ,[current ]

    def _lower_expr (self ,expr :expr ,current :int )->operand :
        if isinstance (expr ,nameexpr ):
            return operand ("slot",self .slot_for_name (expr .name ))
        if isinstance (expr ,borrowexpr ):
            target =self ._lower_expr (expr .target ,current )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (
            assignstmt (slot ,"borrow_mut"if expr .mutable else "borrow",(target ,))
            )
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,self ._operand_type (target ))
            return operand ("slot",slot )
        if isinstance (expr ,unaryexpr ):
            operand =self ._lower_expr (expr .operand ,current )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,f"unary:{expr .op }",(operand ,)))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,unknowntype ("unary"))
            return operand ("slot",slot )
        if isinstance (expr ,binaryexpr ):
            left =self ._lower_expr (expr .left ,current )
            right =self ._lower_expr (expr .right ,current )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,f"binary:{expr .op }",(left ,right )))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,self ._infer_binary_type (expr .op ,left ,right ))
            return operand ("slot",slot )
        if isinstance (expr ,memberexpr ):
            target =self ._lower_expr (expr .target ,current )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,"member",(target ,expr .member )))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,unknowntype (f"member:{expr .member }"))
            return operand ("slot",slot )
        if isinstance (expr ,indexexpr ):
            target =self ._lower_expr (expr .target ,current )
            index =self ._lower_expr (expr .index ,current )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,"index",(target ,index )))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,unknowntype ("index"))
            return operand ("slot",slot )
        if isinstance (expr ,callexpr ):
            callee =self ._lower_expr (expr .callee ,current )
            args =tuple(self ._lower_expr (arg ,current )for arg in expr .args )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,"call",(callee ,*args )))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,unknowntype ("call"))
            return operand ("slot",slot )
        if isinstance (expr ,structliteralexpr ):
            callee =self ._lower_expr (expr .callee ,current )
            fields =tuple((field .name ,self ._lower_expr (field .value ,current ))for field in expr .fields )
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,"struct",(callee ,*fields )))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,unknowntype ("struct"))
            return operand ("slot",slot )
        if isinstance (expr ,blockexpr ):
            slot =self .new_temp ()
            self .blocks [current ].statements .append (assignstmt (slot ,"block",(expr ,)))
            self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,unknowntype ("block"))
            return operand ("slot",slot )
        if hasattr (expr ,"value"):
            return operand ("literal",getattr (expr ,"value"))
        slot =self .new_temp ()
        self .blocks [current ].statements .append (assignstmt (slot ,"expr",(expr ,)))
        self .locals [slot ]=localslot (slot ,f"_t{slot }","temp",0 ,self ._infer_expr_type (expr ))
        return operand ("slot",slot )

    def _emit_drops (self ,block_id :int )->None :
        for slot_id ,slot in sorted (self .locals .items (),reverse =True ):
            if slot .kind in {"local","loop","param"}and self ._decision_for_slot (slot_id ).droppable :
                self .blocks [block_id ].statements .append (dropstmt (slot_id ))

    def _operand_type (self ,operand :operand )->type :
        if operand .kind =="slot":
            return self .locals [operand .value ].ty 
        return unknowntype ("literal")

    def _infer_expr_type (self ,expr :expr )->type :
        if hasattr (expr ,"inferred_type")and getattr (expr ,"inferred_type",None ):
            return parse_type (expr .inferred_type )
        if hasattr (expr ,"value")and isinstance (getattr (expr ,"value"),str )and getattr (expr ,"value").isdigit ():
            return parse_type ("int32")
        return unknowntype ("expr")

    def _infer_binary_type (self ,op :str ,left :operand ,right :operand )->type :
        if op in {"+","-","*","/","%"}:
            return parse_type ("int32")
        if op in {"==","!=","<","<=",">",">=","&&","||"}:
            return parse_type ("bool")
        return unknowntype ("binary")

    def _infer_iter_type (self ,operand :operand )->type :
        if operand .kind =="slot":
            ty =self .locals [operand .value ].ty 
            if hasattr (ty ,"args")and getattr (ty ,"args",None ):
                return ty .args [0 ]
        return unknowntype ("iter_item")
