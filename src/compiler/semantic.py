from __future__ import annotations

from dataclasses import dataclass, field as datfield
from typing import Dict, List, Optional, Set

from compiler.ast import (
    assignstmt,
    binaryexpr,
    blockexpr,
    boolexpr,
    borrowexpr,
    callexpr,
    cforstmt,
    enumdecl,
    expr,
    exprstmt,
    forexpr,
    functiondecl,
    ifexpr,
    impldecl,
    incrementstmt,
    indexexpr,
    intexpr,
    letstmt,
    literalpattern,
    memberexpr,
    nameexpr,
    namepattern,
    param,
    pattern,
    returnstmt,
    sourcefile,
    stringexpr,
    structdecl,
    structliteralexpr,
    switchexpr,
    traitdecl,
    unaryexpr,
    usedecl,
    variantpattern,
    whileexpr,
    wildcardpattern,
)
from compiler.borrow import analyze_block
from compiler.ownership import make_plan
from compiler.prelude import builtinmethoddecl, lookup_builtin_methods, lookup_builtin_type, lookup_index_type
from compiler.typesys import (
    bool,
    dump_type,
    functiontype,
    i32,
    is_copy_type,
    namedtype,
    never,
    parse_type,
    referencetype,
    slicetype,
    string,
    substitute_type,
    type,
    unknowntype,
    unit,
)


@dataclass 
class diagnostic :
    message :str 


@dataclass 
class functioninfo :
    generics :List [str ]
    params :List [type ]
    return_type :type 


@dataclass 
class enuminfo :
    generics :List [str ]
    variants :Dict [str ,Optional [type ]]


@dataclass 
class structinfo :
    fields :Dict [str ,type ]


@dataclass 
class traitmethodinfo :
    owner :str 
    generics :List [str ]
    params :List [type ]
    return_type :type 
    has_receiver :bool =False 
    receiver_mode :str ="value"


@dataclass 
class implinfo :
    trait_name :Optional [str ]
    target :str 
    methods :Dict [str ,traitmethodinfo ]


@dataclass 
class checkresult :
    diagnostics :List [diagnostic ]=datfield(default_factory=list)

    @property 
    def ok (self )->bool :
        return not self .diagnostics 


@dataclass 
class varstate :
    ty :type 
    moved :bool =False 
    shared_borrows :int =0 
    mut_borrowed :bool =False 


def check_source (source :sourcefile )->checkresult :
    checker =checker ()
    checker .load_items (source )
    checker .check (source )
    return checkresult (diagnostics =checker .diagnostics )


class checker :
    def __init__ (self )->None :
        self .diagnostics :List [diagnostic ]=[]
        self .functions :Dict [str ,functioninfo ]={}
        self .enums :Dict [str ,enuminfo ]={}
        self .structs :Dict [str ,structinfo ]={}
        self .variant_to_enum :Dict [str ,str ]={}
        self .imported_functions :Dict [str ,traitmethodinfo ]={}
        self .type_aliases :Dict [str ,str ]={}
        self .traits :Set [str ]={"copy","clone","eq","ord"}
        self .impl_traits :Dict [str ,Set [str ]]={}
        self .trait_methods :Dict [str ,Dict [str ,traitmethodinfo ]]={}
        self .impls :List [implinfo ]=[]
        self ._current_type_env :Dict [str ,type ]={}
        self ._current_return_type :type =unit 
        self .builtin_functions :Dict [str ,traitmethodinfo ]={
        "println":traitmethodinfo (
        owner ="builtin",
        generics =["t"],
        params =[namedtype ("t")],
        return_type =unit ,
        ),
        "eprintln":traitmethodinfo (
        owner ="builtin",
        generics =["t"],
        params =[namedtype ("t")],
        return_type =unit ,
        ),
        "__host_run_shell":traitmethodinfo (
        owner ="builtin",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "__host_run_process1":traitmethodinfo (
        owner ="builtin",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "__host_run_process5":traitmethodinfo (
        owner ="builtin",
        generics =[],
        params =[string ,string ,string ,string ,string ],
        return_type =i32 ,
        ),
        "__host_run_process_argv":traitmethodinfo (
        owner ="builtin",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "__host_build_executable":traitmethodinfo (
        owner ="builtin",
        generics =[],
        params =[string ,string ],
        return_type =i32 ,
        ),
        }
        self ._load_stdlib_primitives ()

    def load_items (self ,source :sourcefile )->None :
        self ._load_use_decls (source .uses )
        for item in source .items :
            if isinstance (item ,functiondecl ):
                self .functions [item .sig .name ]=functioninfo (
                generics =item .sig .generics ,
                params =[self ._normalize_type (parse_type (param .type_name ))for param in item .sig .params ],
                return_type =self ._normalize_type (parse_type (item .sig .return_type or "()")),
                )
            elif isinstance (item ,enumdecl ):
                info =enuminfo (
                generics =item .generics ,
                variants ={
                variant .name :self ._normalize_type (parse_type (variant .payload ))if variant .payload else None 
                for variant in item .variants 
                },
                )
                self .enums [item .name ]=info 
                for variant in item .variants :
                    self .variant_to_enum [variant .name ]=item .name 
            elif isinstance (item ,structdecl ):
                self .structs [item .name ]=structinfo (
                fields ={field .name :self ._normalize_type (parse_type (field .type_name ))for field in item .fields }
                )
            elif isinstance (item ,traitdecl ):
                self .traits .add (item .name )
                self .trait_methods [item .name ]={
                method .name :traitmethodinfo (
                owner =item .name ,
                generics =method .generics ,
                params =[self ._normalize_type (parse_type (param .type_name ))for param in method .params ],
                return_type =self ._normalize_type (parse_type (method .return_type or "()")),
                has_receiver =bool (method .params and method .params [0 ].name =="self"),
                receiver_mode =self ._receiver_mode (method .params [0 ]if method .params else None ),
                )
                for method in item .methods 
                }
            elif isinstance (item ,impldecl ):
                methods ={
                method .sig .name :traitmethodinfo (
                owner =item .target ,
                generics =method .sig .generics ,
                params =[self ._normalize_type (parse_type (param .type_name ))for param in method .sig .params ],
                return_type =self ._normalize_type (parse_type (method .sig .return_type or "()")),
                has_receiver =bool (method .sig .params and method .sig .params [0 ].name =="self"),
                receiver_mode =self ._receiver_mode (method .sig .params [0 ]if method .sig .params else None ),
                )
                for method in item .methods 
                }
                self .impls .append (implinfo (trait_name =item .trait_name ,target =item .target ,methods =methods ))
                if item .trait_name :
                    self .traits .add (item .trait_name )
                    self .impl_traits .setdefault (item .target ,Set ()).add (item .trait_name )

    def check (self ,source :sourcefile )->None :
        for item in source .items :
            if isinstance (item ,functiondecl )and item .body is not None :
                self ._check_function (item )

    def _check_function (self ,item :functiondecl )->None :
        scope :Dict [str ,varstate ]={}
        self ._current_type_env ={}
        previous_return =self ._current_return_type 
        self ._current_return_type =self ._normalize_type (parse_type (item .sig .return_type or "()"))
        for param in item .sig .params :
            ty =self ._normalize_type (parse_type (param .type_name ))
            scope [param .name ]=varstate (ty )
            self ._current_type_env [param .name ]=ty 
        initial_scope =self ._clone_scope (scope )
        self ._check_block (item .body ,scope ,self ._current_return_type )
        cfg_diags =analyze_block (item .body ,initial_scope ,make_plan (self ._current_type_env ))
        for diag in cfg_diags :
            self ._error (diag .message )
        self ._current_return_type =previous_return 

    def _check_block (self ,block :blockexpr ,scope :Dict [str ,varstate ],expected_return :type )->type :
        local_scope =self ._clone_scope (scope )
        terminated =False 
        for stmt in block .statements :
            if self ._check_stmt (stmt ,local_scope ,expected_return ):
                terminated =True 
                break 
        final_type =never if terminated and block .final_expr is None else (
        self ._infer_expr_with_hint (block .final_expr ,local_scope ,expected_return )if block .final_expr is not None else unit 
        )
        if block .final_expr is not None :
            self ._consume_tail_expr (block .final_expr ,local_scope )
        if not self ._type_eq (expected_return ,unit )and block .final_expr is not None and not self ._type_eq (expected_return ,final_type ):
            self ._error (f"block expected {dump_type (expected_return )}, got {dump_type (final_type )}")
        self ._merge_back (scope ,local_scope )
        return final_type 

    def _check_stmt (self ,stmt ,scope :Dict [str ,varstate ],expected_return :type )->bool :
        if isinstance (stmt ,letstmt ):
            value_type =self ._infer_expr (stmt .value ,scope )
            declared =self ._normalize_type (parse_type (stmt .type_name ))if stmt .type_name else None 
            if declared and not self ._type_eq (declared ,value_type ):
                self ._error (f"let {stmt .name } expected {dump_type (declared )}, got {dump_type (value_type )}")
            resolved =declared or value_type 
            scope [stmt .name ]=varstate (resolved )
            self ._current_type_env [stmt .name ]=resolved 
            return False 
        if isinstance (stmt ,assignstmt ):
            state =scope .get (stmt .name )
            if state is None :
                self ._error (f"unresolved name {stmt .name }")
                self ._infer_expr (stmt .value ,scope )
                return False 
            value_type =self ._infer_expr (stmt .value ,scope )
            if not self ._type_eq (state .ty ,value_type ):
                self ._error (f"assign {stmt .name } expected {dump_type (state .ty )}, got {dump_type (value_type )}")
            return False 
        if isinstance (stmt ,incrementstmt ):
            state =scope .get (stmt .name )
            if state is None :
                self ._error (f"unresolved name {stmt .name }")
                return False 
            if not self ._type_eq (state .ty ,i32 ):
                self ._error (f"increment {stmt .name } expected int32, got {dump_type (state .ty )}")
            return False 
        if isinstance (stmt ,cforstmt ):
            loop_scope =self ._clone_scope (scope )
            self ._check_stmt (stmt .init ,loop_scope ,expected_return )
            cond_type =self ._infer_expr (stmt .condition ,loop_scope )
            if not self ._type_eq (cond_type ,bool ):
                self ._error (f"for condition expected bool, got {dump_type (cond_type )}")
            body_scope =self ._clone_scope (loop_scope )
            self ._check_block (stmt .body ,body_scope ,unit )
            self ._check_stmt (stmt .step ,body_scope ,expected_return )
            self ._merge_back (scope ,body_scope )
            return False 
        if isinstance (stmt ,returnstmt ):
            actual =self ._infer_expr_with_hint (stmt .value ,scope ,self ._current_return_type )if stmt .value is not None else unit 
            if not self ._type_eq (self ._current_return_type ,actual ):
                self ._error (f"return expected {dump_type (self ._current_return_type )}, got {dump_type (actual )}")
            return True 
        if isinstance (stmt ,exprstmt ):
            return self ._is_never (self ._infer_expr (stmt .expr ,scope ))
        return False 

    def _infer_expr (self ,expr :Optional [expr ],scope :Dict [str ,varstate ])->type :
        return self ._infer_expr_with_hint (expr ,scope ,None )

    def _infer_expr_with_hint (self ,expr :Optional [expr ],scope :Dict [str ,varstate ],expected_type :Optional [type ])->type :
        if expr is None :
            return unit 
        if isinstance (expr ,intexpr ):
            expr .inferred_type =dump_type (i32 )
            return i32 
        if isinstance (expr ,stringexpr ):
            expr .inferred_type =dump_type (string )
            return string 
        if isinstance (expr ,boolexpr ):
            expr .inferred_type =dump_type (bool )
            return bool 
        if isinstance (expr ,nameexpr ):
            state =scope .get (expr .name )
            if state is None :
                if expr .name in self .variant_to_enum :
                    ty =self ._infer_unit_variant_name (expr .name ,expected_type )
                    expr .inferred_type =dump_type (ty )
                    return ty 
                imported =self .imported_functions .get (expr .name )
                if imported is not None :
                    ty =functiontype (imported .params ,imported .return_type )
                    expr .inferred_type =dump_type (ty )
                    return ty 
                self ._error (f"unresolved name {expr .name }")
                return unknowntype ()
            if state .moved :
                self ._error (f"use of moved value {expr .name }")
            expr .inferred_type =dump_type (state .ty )
            return state .ty 
        if isinstance (expr ,borrowexpr ):
            if isinstance (expr .target ,nameexpr ):
                state =scope .get (expr .target .name )
                if state is None :
                    self ._error (f"unresolved name {expr .target .name }")
                    return unknowntype ()
                if state .moved :
                    self ._error (f"borrow of moved value {expr .target .name }")
                if expr .mutable :
                    if state .shared_borrows >0 or state .mut_borrowed :
                        self ._error (f"cannot mutably borrow {expr .target .name } while borrowed")
                    state .mut_borrowed =True 
                else :
                    if state .mut_borrowed :
                        self ._error (f"cannot immutably borrow {expr .target .name } while mutably borrowed")
                    state .shared_borrows +=1 
                ty =referencetype (state .ty ,mutable =expr .mutable )
                expr .inferred_type =dump_type (ty )
                return ty 
            self ._error ("borrow target must be a name in mvp")
            return unknowntype ()
        if isinstance (expr ,unaryexpr ):
            operand =self ._infer_expr (expr .operand ,scope )
            if expr .op =="!":
                if not self ._type_eq (operand ,bool ):
                    self ._error (f"operator ! expects bool, got {dump_type (operand )}")
                expr .inferred_type =dump_type (bool )
                return bool 
            self ._error (f"unknown unary operator {expr .op }")
            return unknowntype ()
        if isinstance (expr ,binaryexpr ):
            left =self ._infer_expr (expr .left ,scope )
            right =self ._infer_expr (expr .right ,scope )
            result =self ._infer_binary (expr .op ,left ,right )
            expr .inferred_type =dump_type (result )
            return result 
        if isinstance (expr ,memberexpr ):
            target =self ._inspect_expr_type (expr .target ,scope )
            member_type =self ._resolve_member (target ,expr .member )
            if member_type is None :
                self ._error (f"unknown member {expr .member } on {dump_type (target )}")
                return unknowntype ()
            expr .inferred_type =dump_type (member_type )
            return member_type 
        if isinstance (expr ,indexexpr ):
            target =self ._inspect_expr_type (expr .target ,scope )
            index =self ._infer_expr (expr .index ,scope )
            if not self ._type_eq (index ,i32 ):
                self ._error (f"index expected int32, got {dump_type (index )}")
            result =self ._resolve_index (target )
            expr .inferred_type =dump_type (result )
            return result 
        if isinstance (expr ,callexpr ):
            variant_result =self ._infer_variant_constructor_call (expr ,scope ,expected_type )
            if variant_result is not None :
                expr .inferred_type =dump_type (variant_result )
                return variant_result 
            constructed =self ._infer_type_constructor_call (expr .callee ,expr .args )
            if constructed is not None :
                expr .inferred_type =dump_type (constructed )
                return constructed 
            if isinstance (expr .callee ,memberexpr ):
                method_info =self ._resolve_method_call (expr .callee ,expr .args ,scope )
                if method_info is not None :
                    return self ._check_callable (method_info ,expr .args ,scope ,expr .callee .member ,expr )
            if isinstance (expr .callee ,nameexpr )and expr .callee .name in self .functions :
                info =self .functions [expr .callee .name ]
                method_like =traitmethodinfo (
                owner =expr .callee .name ,
                generics =info .generics ,
                params =info .params ,
                return_type =info .return_type ,
                )
                return self ._check_callable (method_like ,expr .args ,scope ,expr .callee .name ,expr )
            if isinstance (expr .callee ,nameexpr )and expr .callee .name in self .builtin_functions :
                return self ._check_callable (
                self .builtin_functions [expr .callee .name ],
                expr .args ,
                scope ,
                expr .callee .name ,
                expr ,
                )
            if isinstance (expr .callee ,nameexpr )and expr .callee .name in self .imported_functions :
                return self ._check_callable (
                self .imported_functions [expr .callee .name ],
                expr .args ,
                scope ,
                expr .callee .name ,
                expr ,
                )
            self ._infer_expr (expr .callee ,scope )
            for arg in expr .args :
                self ._infer_expr (arg ,scope )
            return unknowntype ()
        if isinstance (expr ,structliteralexpr ):
            struct_type =self ._infer_struct_literal_type (expr .callee )
            if struct_type is None :
                for field in expr .fields :
                    self ._infer_expr (field .value ,scope )
                self ._error ("unknown struct literal target")
                return unknowntype ()
            struct_name =dump_type (struct_type )
            struct_info =self .structs .get (struct_name )
            if struct_info is None :
                for field in expr .fields :
                    self ._infer_expr (field .value ,scope )
                self ._error (f"unknown struct {struct_name }")
                expr .inferred_type =dump_type (struct_type )
                return struct_type 
            seen :Set [str ]=Set ()
            for field in expr .fields :
                if field .name in seen :
                    self ._error (f"duplicate struct field {field .name }")
                    continue 
                seen .add (field .name )
                expected_field_type =struct_info .fields .get (field .name )
                actual_field_type =self ._infer_expr (field .value ,scope )
                if expected_field_type is None :
                    self ._error (f"unknown field {field .name } on {struct_name }")
                    continue 
                if not self ._type_eq (expected_field_type ,actual_field_type ):
                    self ._error (
                    f"field {field .name } expected {dump_type (expected_field_type )}, got {dump_type (actual_field_type )}"
                    )
            expr .inferred_type =dump_type (struct_type )
            return struct_type 
        if isinstance (expr ,blockexpr ):
            ty =self ._check_block (expr ,scope ,unit )
            expr .inferred_type =dump_type (ty )
            return ty 
        if isinstance (expr ,ifexpr ):
            cond =self ._infer_expr (expr .condition ,scope )
            if not self ._type_eq (cond ,bool ):
                self ._error (f"if condition expected bool, got {dump_type (cond )}")
            then_scope =self ._clone_scope (scope )
            then_type =self ._check_block (expr .then_branch ,then_scope ,expected_type or unit )
            else_type =unit 
            else_scope =self ._clone_scope (scope )
            if expr .else_branch is not None :
                else_type =self ._infer_expr_with_hint (expr .else_branch ,else_scope ,expected_type )
            self ._join_scopes (scope ,then_scope ,else_scope )
            if expr .else_branch is None :
                expr .inferred_type =dump_type (unit )
                return unit 
            if self ._is_never (then_type ):
                expr .inferred_type =dump_type (else_type )
                return else_type 
            if self ._is_never (else_type ):
                expr .inferred_type =dump_type (then_type )
                return then_type 
            if not self ._type_eq (then_type ,else_type ):
                self ._error (f"if branch type mismatch: {dump_type (then_type )} vs {dump_type (else_type )}")
                return unknowntype ()
            expr .inferred_type =dump_type (then_type )
            return then_type 
        if isinstance (expr ,whileexpr ):
            cond =self ._infer_expr (expr .condition ,scope )
            if not self ._type_eq (cond ,bool ):
                self ._error (f"while condition expected bool, got {dump_type (cond )}")
            body_scope =self ._clone_scope (scope )
            self ._check_block (expr .body ,body_scope ,unit )
            self ._join_scopes (scope ,body_scope ,scope )
            expr .inferred_type =dump_type (unit )
            return unit 
        if isinstance (expr ,forexpr ):
            iter_type =self ._infer_expr (expr .iterable ,scope )
            body_scope =self ._clone_scope (scope )
            item_type =self ._infer_iter_item (iter_type )
            body_scope [expr .name ]=varstate (item_type )
            self ._current_type_env .setdefault (expr .name ,item_type )
            self ._check_block (expr .body ,body_scope ,unit )
            self ._join_scopes (scope ,body_scope ,scope )
            expr .inferred_type =dump_type (unit )
            return unit 
        if isinstance (expr ,switchexpr ):
            subject_type =self ._infer_expr (expr .subject ,scope )
            arm_type :Optional [type ]=None 
            arm_scopes =[]
            for arm in expr .arms :
                arm_scope =self ._clone_scope (scope )
                self ._bind_pattern (arm .pattern ,subject_type ,arm_scope )
                current =self ._infer_expr_with_hint (arm .expr ,arm_scope ,expected_type )
                arm_scopes .append (arm_scope )
                if self ._is_never (current ):
                    continue 
                if arm_type is None or self ._is_never (arm_type ):
                    arm_type =current 
                elif not self ._type_eq (arm_type ,current ):
                    self ._error (f"switch arm type mismatch: {dump_type (arm_type )} vs {dump_type (current )}")
            if arm_scopes :
                merged =arm_scopes [0 ]
                for extra in arm_scopes [1 :]:
                    self ._join_scopes (merged ,merged ,extra )
                self ._merge_back (scope ,merged )
            result =arm_type or unknowntype ()
            expr .inferred_type =dump_type (result )
            return result 
        self ._error (f"unhandled expr {type (expr ).__name__ }")
        return unknowntype ()

    def _infer_variant_constructor_call (
    self ,
    expr :callexpr ,
    scope :Dict [str ,varstate ],
    expected_type :Optional [type ],
    )->Optional [type ]:
        if not isinstance (expr .callee ,nameexpr ):
            return None 
        variant_name =self ._variant_name (expr .callee .name )
        enum_name =self .variant_to_enum .get (variant_name )
        if enum_name is None :
            return None 
        expected_type =self ._normalize_type (expected_type )if expected_type is not None else None 
        if not isinstance (expected_type ,namedtype )or expected_type .name !=enum_name :
            for arg in expr .args :
                self ._infer_expr (arg ,scope )
            return unknowntype ()
        payload_type =self ._resolve_variant_payload_type (variant_name ,expected_type )
        if payload_type is None :
            if expr .args :
                self ._error (f"variant {variant_name } does not take payload")
            return expected_type 
        if len (expr .args )!=1 :
            self ._error (f"variant {variant_name } expects 1 payload")
            return expected_type 
        actual_payload =self ._infer_expr (expr .args [0 ],scope )
        if not self ._type_eq (payload_type ,actual_payload ):
            self ._error (f"call {variant_name } expected {dump_type (payload_type )}, got {dump_type (actual_payload )}")
        return expected_type 

    def _infer_unit_variant_name (self ,name :str ,expected_type :Optional [type ])->type :
        variant_name =self ._variant_name (name )
        enum_name =self .variant_to_enum .get (variant_name )
        normalized_expected =self ._normalize_type (expected_type )if expected_type is not None else None 
        if isinstance (normalized_expected ,namedtype )and normalized_expected .name ==enum_name :
            payload_type =self ._resolve_variant_payload_type (variant_name ,normalized_expected )
            if payload_type is None :
                return normalized_expected 
        return namedtype (name )

    def _infer_type_constructor_call (self ,callee :expr ,args :List [expr ])->Optional [type ]:
        if isinstance (callee ,indexexpr )and isinstance (callee .target ,nameexpr ):
            base =self .type_aliases .get (callee .target .name ,callee .target .name )
            if base =="vec":
                element =self ._type_from_expr (callee .index )
                if element is not None :
                    return namedtype ("vec",[element ])
        if isinstance (callee ,nameexpr ):
            base =self .type_aliases .get (callee .name ,callee .name )
            if base =="vec":
                return namedtype ("vec")
        return None 

    def _infer_struct_literal_type (self ,callee :expr )->Optional [type ]:
        if isinstance (callee ,nameexpr ):
            return self ._normalize_type (parse_type (callee .name ))
        if isinstance (callee ,indexexpr )and isinstance (callee .target ,nameexpr ):
            base =self .type_aliases .get (callee .target .name ,callee .target .name )
            inner =self ._type_from_expr (callee .index )
            if inner is not None :
                return namedtype (base ,[inner ])
        return self ._type_from_expr (callee )

    def _is_never (self ,ty :type )->bool :
        return isinstance (self ._normalize_type (ty ),type (never ))

    def _consume_tail_expr (self ,expr :expr ,scope :Dict [str ,varstate ])->None :
        if isinstance (expr ,nameexpr ):
            state =scope .get (expr .name )
            if state is None :
                return 
            if not is_copy_type (state .ty ):
                state .moved =True 

    def _type_from_expr (self ,expr :expr )->Optional [type ]:
        if isinstance (expr ,nameexpr ):
            return self ._normalize_type (parse_type (expr .name ))
        if isinstance (expr ,indexexpr )and isinstance (expr .target ,nameexpr ):
            base =self .type_aliases .get (expr .target .name ,expr .target .name )
            inner =self ._type_from_expr (expr .index )
            if inner is not None :
                return namedtype (base ,[inner ])
        return None 

    def _bind_pattern (self ,pattern :pattern ,subject_type :type ,scope :Dict [str ,varstate ])->None :
        if isinstance (pattern ,wildcardpattern ):
            return 
        if isinstance (pattern ,namepattern ):
            scope [pattern .name ]=varstate (subject_type )
            return 
        if isinstance (pattern ,literalpattern ):
            literal_type =self ._literal_pattern_type (pattern )
            if literal_type is None :
                self ._error (f"unsupported literal pattern {type (pattern .value ).__name__ }")
                return 
            if not self ._type_eq (literal_type ,subject_type ):
                self ._error (f"literal pattern type mismatch: {dump_type (literal_type )} vs {dump_type (subject_type )}")
            return 
        if isinstance (pattern ,variantpattern ):
            variant_name =self ._variant_name (pattern .path )
            expected_payload =self ._resolve_variant_payload_type (variant_name ,subject_type )
            if variant_name not in self .variant_to_enum :
                self ._error (f"unknown switch variant {pattern .path }")
            if expected_payload is None and pattern .args :
                self ._error (f"variant {pattern .path } does not take payload")
            if expected_payload is not None and len (pattern .args )!=1 :
                self ._error (f"variant {pattern .path } expects 1 payload")
            for arg in pattern .args :
                self ._bind_pattern (arg ,expected_payload or unknowntype (),scope )

    def _resolve_variant_payload_type (self ,variant_name :str ,subject_type :type )->Optional [type ]:
        subject_type =self ._normalize_type (subject_type )
        enum_name =self .variant_to_enum .get (variant_name )
        if enum_name is None :
            return None 
        enum_info =self .enums .get (enum_name )
        if enum_info is None :
            return None 
        payload =enum_info .variants .get (variant_name )
        if payload is None :
            return None 
        if isinstance (subject_type ,namedtype )and subject_type .name ==enum_name :
            mapping ={name :arg for name ,arg in zip (enum_info .generics ,subject_type .args )}
            return substitute_type (payload ,mapping )
        return payload 

    def _literal_pattern_type (self ,pattern :literalpattern )->Optional [type ]:
        if isinstance (pattern .value ,intexpr ):
            return i32 
        if isinstance (pattern .value ,stringexpr ):
            return string 
        if isinstance (pattern .value ,boolexpr ):
            return bool 
        return None 

    def _infer_binary (self ,op :str ,left :type ,right :type )->type :
        left =self ._normalize_type (left )
        right =self ._normalize_type (right )
        if op =="+":
            if self ._type_eq (left ,i32 )and self ._type_eq (right ,i32 ):
                return i32 
            if self ._type_eq (left ,string )and self ._type_eq (right ,string ):
                return string 
            self ._error (f"operator + expects matching int32/string operands, got {dump_type (left )} and {dump_type (right )}")
            return unknowntype ()
        if op in {"+","-","*","/","%"}:
            if self ._type_eq (left ,i32 )and self ._type_eq (right ,i32 ):
                return i32 
            self ._error (f"operator {op } expects int32 operands, got {dump_type (left )} and {dump_type (right )}")
            return unknowntype ()
        if op in {"==","!=","<","<=",">",">="}:
            if self ._type_eq (left ,right ):
                return bool 
            self ._error (f"operator {op } expects matching operand types, got {dump_type (left )} and {dump_type (right )}")
            return bool 
        if op in {"&&","||"}:
            if self ._type_eq (left ,bool )and self ._type_eq (right ,bool ):
                return bool 
            self ._error (f"operator {op } expects bool operands, got {dump_type (left )} and {dump_type (right )}")
            return bool 
        self ._error (f"unknown operator {op }")
        return unknowntype ()

    def _type_eq (self ,left :type ,right :type )->bool :
        return dump_type (self ._normalize_type (left ))==dump_type (self ._normalize_type (right ))

    def _unify_types (self ,expected :type ,actual :type ,subst :Dict [str ,type ])->bool :
        if isinstance (expected ,namedtype )and not expected .args and expected .name .isupper ():
            bound =subst .get (expected .name )
            if bound is None :
                subst [expected .name ]=actual 
                return True 
            return self ._type_eq (bound ,actual )
        if isinstance (expected ,namedtype )and isinstance (actual ,namedtype ):
            if expected .name !=actual .name or len (expected .args )!=len (actual .args ):
                return False 
            return all (self ._unify_types (e ,a ,subst )for e ,a in zip (expected .args ,actual .args ))
        if isinstance (expected ,referencetype )and isinstance (actual ,referencetype ):
            if expected .mutable !=actual .mutable :
                return False 
            return self ._unify_types (expected .inner ,actual .inner ,subst )
        return self ._type_eq (expected ,actual )

    def _check_generic_bounds (self ,generic_specs :List [str ],subst :Dict [str ,type ])->bool :
        ok =True 
        for spec in generic_specs :
            if ":"not in spec :
                continue 
            name ,bounds_text =spec .split (":",1 )
            ty =subst .get (name .strip ())
            if ty is None :
                continue 
            for bound in [part .strip ()for part in bounds_text .split ("+")]:
                if not self ._implements_trait (ty ,bound ):
                    self ._error (f"type {dump_type (ty )} does not satisfy bound {bound }")
                    ok =False 
        return ok 

    def _implements_trait (self ,ty :type ,trait_name :str )->bool :
        if trait_name =="copy":
            return is_copy_type (ty )
        if trait_name =="clone":
            return is_copy_type (ty )or dump_type (ty )in {"string"}
        builtin =lookup_builtin_type (ty )
        if builtin is not None and trait_name in builtin .traits :
            return True 
        name =dump_type (ty )
        return trait_name in self .impl_traits .get (name ,Set ())

    def _infer_iter_item (self ,ty :type )->type :
        if isinstance (ty ,namedtype )and ty .name =="vec"and ty .args :
            return ty .args [0 ]
        if isinstance (ty ,slicetype ):
            return ty .inner 
        if isinstance (ty ,referencetype ):
            return ty .inner 
        return unknowntype ("iter_item")

    def _resolve_index (self ,target :type )->type :
        resolved =lookup_index_type (target )
        return resolved or unknowntype ("index")

    def _resolve_member (self ,target :type ,member :str )->Optional [type ]:
        if isinstance (target ,referencetype ):
            return self ._resolve_member (target .inner ,member )
        if isinstance (target ,namedtype ):
            if target .name =="option":
                if member =="is_some"or member =="is_none":
                    return bool 
                if member =="unwrap"and target .args :
                    return target .args [0 ]
                if member =="unwrap_or"and target .args :
                    return target .args [0 ]
            struct_info =self .structs .get (target .name )
            if struct_info and member in struct_info .fields :
                return struct_info .fields [member ]
            builtin_type =lookup_builtin_type (target )
            if builtin_type is not None and member in builtin_type .fields :
                field =builtin_type .fields [member ]
                if not field .readable :
                    self ._error (f"field {member } on {dump_type (target )} is not readable")
                    return None 
                return field .ty 
            method_sig =self ._lookup_method (target ,member )
            if method_sig is not None :
                return functiontype (method_sig .params ,method_sig .return_type )
            builtins =lookup_builtin_methods (target ,member )
            if len (builtins )==1 :
                return builtins [0 ].signature 
            if len (builtins )>1 :
                self ._error (f"cannot refer to overloaded builtin method {member } without call")
                return None 
        return None 

    def _resolve_method_call (
    self ,
    callee :memberexpr ,
    args :List [expr ],
    scope :Dict [str ,varstate ],
    )->Optional [traitmethodinfo ]:
        receiver_type =self ._inspect_expr_type (callee .target ,scope )
        method_sig =self ._lookup_method (receiver_type ,callee .member )
        if method_sig is None :
            builtin =self ._select_builtin_method (receiver_type ,callee .member ,callee .target ,args ,scope )
            if builtin is not None :
                return traitmethodinfo (
                "builtin",
                [],
                builtin .signature .params ,
                builtin .signature .return_type or unit ,
                False ,
                builtin .receiver_mode ,
                )
            self ._error (f"no method {callee .member } for {dump_type (receiver_type )}")
            return None 
        self ._validate_receiver (method_sig ,receiver_type ,callee .target ,callee .member )
        params =method_sig .params 
        if method_sig .has_receiver and params :
            params =params [1 :]
        return traitmethodinfo (
        method_sig .owner ,
        method_sig .generics ,
        params ,
        method_sig .return_type ,
        has_receiver =False ,
        receiver_mode =method_sig .receiver_mode ,
        )

    def _lookup_method (self ,receiver_type :type ,method_name :str )->Optional [traitmethodinfo ]:
        receiver_name =dump_type (receiver_type .inner if isinstance (receiver_type ,referencetype )else receiver_type )
        candidates :List [traitmethodinfo ]=[]
        for impl_info in self .impls :
            if impl_info .target ==receiver_name and method_name in impl_info .methods :
                candidates .append (impl_info .methods [method_name ])
        if len (candidates )>1 :
            owners =", ".join (candidate .owner for candidate in candidates )
            self ._error (f"multiple method candidates for {receiver_name }.{method_name }: {owners }")
            return candidates [0 ]
        return candidates [0 ]if candidates else None 

    def _select_builtin_method (
    self ,
    receiver_type :type ,
    method_name :str ,
    receiver_expr :expr ,
    expr_args :List [expr ],
    scope :Dict [str ,varstate ],
    )->Optional [traitmethodinfo ]:
        if isinstance (receiver_type ,namedtype )and receiver_type .name =="option":
            option_inner =receiver_type .args [0 ]if receiver_type .args else unknowntype ()
            if method_name =="is_some"or method_name =="is_none":
                return builtinmethoddecl (
                name =method_name ,
                trait_name =None ,
                receiver_mode ="ref",
                receiver_policy ="shared_or_addressable",
                signature =functiontype ([],bool ),
                )
            if method_name =="unwrap":
                return builtinmethoddecl (
                name =method_name ,
                trait_name =None ,
                receiver_mode ="ref",
                receiver_policy ="shared_or_addressable",
                signature =functiontype ([],option_inner ),
                )
            if method_name =="unwrap_or":
                return builtinmethoddecl (
                name =method_name ,
                trait_name =None ,
                receiver_mode ="ref",
                receiver_policy ="shared_or_addressable",
                signature =functiontype ([option_inner ],option_inner ),
                )
        candidates =list(lookup_builtin_methods (receiver_type ,method_name ))
        if not candidates :
            return None 
        arity_matches =[candidate for candidate in candidates if len (candidate .signature .params )==len (expr_args )]
        if not arity_matches :
            self ._error (f"call {method_name } expected one of {[len (c .signature .params )for c in candidates ]} args, got {len (expr_args )}")
            return candidates [0 ]
        viable =[]
        for candidate in arity_matches :
            if self ._builtin_receiver_ok (candidate ,receiver_type ,receiver_expr ):
                viable .append (candidate )
        if not viable :
            self ._validate_builtin_receiver (arity_matches [0 ],receiver_type ,receiver_expr ,method_name )
            return arity_matches [0 ]
        if len (viable )>1 :
            self ._error (f"multiple builtin overloads for {dump_type (receiver_type )}.{method_name }")
            return viable [0 ]
        return viable [0 ]

    def _check_callable (
    self ,
    info :traitmethodinfo ,
    args :List [expr ],
    scope :Dict [str ,varstate ],
    name :str ,
    owner_expr :expr ,
    )->type :
        if len (info .params )!=len (args ):
            self ._error (f"call {name } expected {len (info .params )} args, got {len (args )}")
        subst :Dict [str ,type ]={}
        for arg ,param_type in zip (args ,info .params ):
            arg_type =self ._infer_expr (arg ,scope )
            if not self ._unify_types (param_type ,arg_type ,subst ):
                self ._error (f"call {name } expected {dump_type (param_type )}, got {dump_type (arg_type )}")
        if not self ._check_generic_bounds (info .generics ,subst ):
            owner_expr .inferred_type =dump_type (unknowntype ())
            return unknowntype ()
        resolved_return =substitute_type (info .return_type ,subst )
        owner_expr .inferred_type =dump_type (resolved_return )
        return resolved_return 

    def _inspect_expr_type (self ,expr :expr ,scope :Dict [str ,varstate ])->type :
        if isinstance (expr ,nameexpr ):
            state =scope .get (expr .name )
            if state is None :
                if expr .name in self .variant_to_enum :
                    return namedtype (expr .name )
                imported =self .imported_functions .get (expr .name )
                if imported is not None :
                    return functiontype (imported .params ,imported .return_type )
                self ._error (f"unresolved name {expr .name }")
                return unknowntype ()
            if state .moved :
                self ._error (f"use of moved value {expr .name }")
            return state .ty 
        return self ._infer_expr (expr ,scope )

    def _load_stdlib_primitives (self )->None :
        self .enums ["option"]=enuminfo (generics =["t"],variants ={"some":namedtype ("t"),"none":None })
        self .enums ["result"]=enuminfo (
        generics =["t","e"],
        variants ={"ok":namedtype ("t"),"err":namedtype ("e")},
        )
        self .variant_to_enum .update (
        {
        "some":"option",
        "none":"option",
        "ok":"result",
        "err":"result",
        }
        )
        self .structs .setdefault ("fserror",structinfo (fields ={"message":string }))
        self .structs .setdefault ("processerror",structinfo (fields ={"message":string }))
        self .structs .setdefault ("clierror",structinfo (fields ={"message":string }))
        self .structs .setdefault (
        "compileoptions",
        structinfo (fields ={"command":string ,"path":string ,"output":string }),
        )
        self .structs .setdefault ("usedecl",structinfo (fields ={"path":string ,"alias":parse_type ("option[string]")}))
        self .structs .setdefault (
        "field",
        structinfo (fields ={"name":string ,"type_name":string ,"is_public":bool }),
        )
        self .structs .setdefault (
        "param",
        structinfo (fields ={"name":string ,"type_name":string }),
        )
        self .structs .setdefault (
        "functionsig",
        structinfo (
        fields ={
        "name":string ,
        "generics":parse_type ("vec[string]"),
        "params":parse_type ("vec[param]"),
        "return_type":parse_type ("option[string]"),
        }
        ),
        )
        self .structs .setdefault (
        "blockexpr",
        structinfo (
        fields ={
        "statements":parse_type ("vec[stmt]"),
        "final_expr":parse_type ("option[expr]"),
        }
        ),
        )
        self .structs .setdefault ("functiondecl",structinfo (fields ={"sig":namedtype ("functionsig"),"body":parse_type ("option[blockexpr]"),"is_public":bool }))
        self .structs .setdefault (
        "sourcefile",
        structinfo (fields ={"pkg":string ,"uses":parse_type ("vec[usedecl]"),"items":parse_type ("vec[item]")}),
        )
        self .structs .setdefault ("syntaxerror",structinfo (fields ={"message":string ,"line":i32 ,"column":i32 }))
        self .structs .setdefault ("parseerror",structinfo (fields ={"message":string }))
        self .structs .setdefault ("execerror",structinfo (fields ={"message":string }))
        self .structs .setdefault ("backenderror",structinfo (fields ={"message":string }))
        self .enums .setdefault (
        "item",
        enuminfo (
        generics =[],
        variants ={
        "function":namedtype ("functiondecl"),
        "struct":namedtype ("structdecl"),
        "enum":namedtype ("enumdecl"),
        "trait":namedtype ("traitdecl"),
        "impl":namedtype ("impldecl"),
        },
        ),
        )

    def _load_use_decls (self ,uses :List [usedecl ])->None :
        for use in uses :
            local_name =use .alias or use .path .split (".")[-1 ]
            canonical_name =use .path .split (".")[-1 ]
            self .type_aliases [local_name ]=canonical_name 
            imported =self ._builtin_for_use (use .path ,local_name )
            if imported is not None :
                self .imported_functions [local_name ]=imported 

    def _builtin_for_use (self ,path :str ,local_name :str )->Optional [traitmethodinfo ]:
        std_functions ={
        "std.env.args":traitmethodinfo (owner ="std.env",generics =[],params =[],return_type =parse_type ("vec[string]")),
        "std.env.get":traitmethodinfo (
        owner ="std.env",
        generics =[],
        params =[string ],
        return_type =parse_type ("option[string]"),
        ),
        "std.fs.readtostring":traitmethodinfo (
        owner ="std.fs",
        generics =[],
        params =[string ],
        return_type =parse_type ("result[string, fserror]"),
        ),
        "std.fs.writetextfile":traitmethodinfo (
        owner ="std.fs",
        generics =[],
        params =[string ,string ],
        return_type =parse_type ("result[(), fserror]"),
        ),
        "std.fs.maketempdir":traitmethodinfo (
        owner ="std.fs",
        generics =[],
        params =[string ],
        return_type =parse_type ("result[string, fserror]"),
        ),
        "std.io.println":traitmethodinfo (owner ="std.io",generics =["t"],params =[namedtype ("t")],return_type =unit ),
        "std.io.eprintln":traitmethodinfo (owner ="std.io",generics =["t"],params =[namedtype ("t")],return_type =unit ),
        "std.prelude.len":traitmethodinfo (owner ="std.prelude",generics =["t"],params =[namedtype ("t")],return_type =i32 ),
        "std.prelude.to_string":traitmethodinfo (owner ="std.prelude",generics =[],params =[i32 ],return_type =string ),
        "std.prelude.char_at":traitmethodinfo (owner ="std.prelude",generics =[],params =[string ,i32 ],return_type =string ),
        "std.prelude.slice":traitmethodinfo (owner ="std.prelude",generics =[],params =[string ,i32 ,i32 ],return_type =string ),
        "s.dump_stmt":traitmethodinfo (
        owner ="s",
        generics =[],
        params =[parse_type ("stmt"),string ],
        return_type =parse_type ("vec[string]"),
        ),
        "s.dump_expr":traitmethodinfo (
        owner ="s",
        generics =[],
        params =[parse_type ("expr")],
        return_type =string ,
        ),
        "compile.internal.syntax.readsource":traitmethodinfo (
        owner ="compile.internal.syntax",
        generics =[],
        params =[string ],
        return_type =parse_type ("result[string, syntaxerror]"),
        ),
        "compile.internal.syntax.tokenize":traitmethodinfo (
        owner ="compile.internal.syntax",
        generics =[],
        params =[string ],
        return_type =parse_type ("result[vec[token], syntaxerror]"),
        ),
        "compile.internal.syntax.parsesource":traitmethodinfo (
        owner ="compile.internal.syntax",
        generics =[],
        params =[string ],
        return_type =parse_type ("result[sourcefile, syntaxerror]"),
        ),
        "compile.internal.syntax.dumptokenstext":traitmethodinfo (
        owner ="compile.internal.syntax",
        generics =[],
        params =[parse_type ("vec[token]")],
        return_type =string ,
        ),
        "compile.internal.syntax.dumpsourcetext":traitmethodinfo (
        owner ="compile.internal.syntax",
        generics =[],
        params =[parse_type ("sourcefile")],
        return_type =string ,
        ),
        "compile.internal.typesys.basetypename":traitmethodinfo (
        owner ="compile.internal.typesys",
        generics =[],
        params =[string ],
        return_type =string ,
        ),
        "compile.internal.typesys.iscopytype":traitmethodinfo (
        owner ="compile.internal.typesys",
        generics =[],
        params =[string ],
        return_type =bool ,
        ),
        "compile.internal.check.loadfrontend":traitmethodinfo (
        owner ="compile.internal.check",
        generics =[],
        params =[string ],
        return_type =string ,
        ),
        "compile.internal.semantic.checktext":traitmethodinfo (
        owner ="compile.internal.semantic",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "std.process.exit":traitmethodinfo (owner ="std.process",generics =[],params =[i32 ],return_type =unit ),
        "std.process.runprocess":traitmethodinfo (
        owner ="std.process",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =parse_type ("result[(), processerror]"),
        ),
        "__host_build_executable":traitmethodinfo (
        owner ="runtime",
        generics =[],
        params =[string ,string ],
        return_type =i32 ,
        ),
        "compile.internal.compiler.main":traitmethodinfo (
        owner ="compile.internal.compiler",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =i32 ,
        ),
        "compile.internal.gc.main":traitmethodinfo (
        owner ="compile.internal.gc",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =i32 ,
        ),
        "compile.internal.build.main":traitmethodinfo (
        owner ="compile.internal.build",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =i32 ,
        ),
        "compile.internal.build.report.error":traitmethodinfo (
        owner ="compile.internal.build.report",
        generics =[],
        params =[string ],
        return_type =unit ,
        ),
        "compile.internal.build.parse.parseoptions":traitmethodinfo (
        owner ="compile.internal.build.parse",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =parse_type ("vec[string]"),
        ),
        "compile.internal.build.exec.run":traitmethodinfo (
        owner ="compile.internal.build.exec",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =i32 ,
        ),
        "compile.internal.build.backend.build":traitmethodinfo (
        owner ="compile.internal.build.backend",
        generics =[],
        params =[string ,string ],
        return_type =i32 ,
        ),
        "compile.internal.build.backend.run":traitmethodinfo (
        owner ="compile.internal.build.backend",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "compile.internal.backend_elf64.build":traitmethodinfo (
        owner ="compile.internal.backend_elf64",
        generics =[],
        params =[string ,string ],
        return_type =i32 ,
        ),
        "compile.internal.tests.test_semantic.runsemanticsuite":traitmethodinfo (
        owner ="compile.internal.tests.test_semantic",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "compile.internal.tests.test_golden.rungoldensuite":traitmethodinfo (
        owner ="compile.internal.tests.test_golden",
        generics =[],
        params =[string ],
        return_type =i32 ,
        ),
        "compile.internal.tests.test_mir.runmirsuite":traitmethodinfo (
        owner ="compile.internal.tests.test_mir",
        generics =[],
        params =[],
        return_type =i32 ,
        ),
        "compile.internal.build.emit.checkok":traitmethodinfo (
        owner ="compile.internal.build.emit",
        generics =[],
        params =[string ],
        return_type =unit ,
        ),
        "compile.internal.build.emit.tokens":traitmethodinfo (
        owner ="compile.internal.build.emit",
        generics =[],
        params =[parse_type ("vec[token]")],
        return_type =unit ,
        ),
        "compile.internal.build.emit.ast":traitmethodinfo (
        owner ="compile.internal.build.emit",
        generics =[],
        params =[parse_type ("sourcefile")],
        return_type =unit ,
        ),
        "compile.internal.build.emit.built":traitmethodinfo (
        owner ="compile.internal.build.emit",
        generics =[],
        params =[string ],
        return_type =unit ,
        ),
        "compile.internal.borrow.analyzeblock":traitmethodinfo (
        owner ="compile.internal.borrow",
        generics =[],
        params =[],
        return_type =i32 ,
        ),
        "compile.internal.borrow.analyzetrace":traitmethodinfo (
        owner ="compile.internal.borrow",
        generics =[],
        params =[string ,parse_type ("vec[string]"),string ],
        return_type =string ,
        ),
        "compile.internal.borrow.analyzefunction":traitmethodinfo (
        owner ="compile.internal.borrow",
        generics =[],
        params =[string ,parse_type ("vec[string]"),string ],
        return_type =string ,
        ),
        "compile.internal.borrow.analyzeexpr":traitmethodinfo (
        owner ="compile.internal.borrow",
        generics =[],
        params =[string ,string ],
        return_type =string ,
        ),
        "compile.internal.mir.lowerfunction":traitmethodinfo (
        owner ="compile.internal.mir",
        generics =[],
        params =[parse_type ("functiondecl")],
        return_type =string ,
        ),
        "compile.internal.mir.lowerblock":traitmethodinfo (
        owner ="compile.internal.mir",
        generics =[],
        params =[parse_type ("blockexpr")],
        return_type =string ,
        ),
        "compile.internal.mir.tracebranch":traitmethodinfo (
        owner ="compile.internal.mir",
        generics =[],
        params =[string ,string ,string ],
        return_type =string ,
        ),
        "compile.internal.mir.traceloop":traitmethodinfo (
        owner ="compile.internal.mir",
        generics =[],
        params =[string ,string ,string ],
        return_type =string ,
        ),
        "compile.internal.mir.traceswitch":traitmethodinfo (
        owner ="compile.internal.mir",
        generics =[],
        params =[string ,string ],
        return_type =string ,
        ),
        "compile.internal.dispatch.main":traitmethodinfo (
        owner ="compile.internal.dispatch",
        generics =[],
        params =[parse_type ("vec[string]")],
        return_type =i32 ,
        ),
        "compile.internal.arch.init":traitmethodinfo (
        owner ="compile.internal.arch",
        generics =[],
        params =[string ],
        return_type =string ,
        ),
        "internal.buildcfg.check":traitmethodinfo (
        owner ="internal.buildcfg",
        generics =[],
        params =[],
        return_type =string ,
        ),
        "internal.buildcfg.goarch":traitmethodinfo (
        owner ="internal.buildcfg",
        generics =[],
        params =[],
        return_type =string ,
        ),
        "compile.internal.amd64.init":traitmethodinfo (owner ="compile.internal.amd64",generics =[],params =[],return_type =unit ),
        "compile.internal.arm64.init":traitmethodinfo (owner ="compile.internal.arm64",generics =[],params =[],return_type =unit ),
        "compile.internal.riscv64.init":traitmethodinfo (owner ="compile.internal.riscv64",generics =[],params =[],return_type =unit ),
        "compile.internal.amd64p32.init":traitmethodinfo (owner ="compile.internal.amd64p32",generics =[],params =[],return_type =unit ),
        "compile.internal.s390x.init":traitmethodinfo (owner ="compile.internal.s390x",generics =[],params =[],return_type =unit ),
        "compile.internal.wasm.init":traitmethodinfo (owner ="compile.internal.wasm",generics =[],params =[],return_type =unit ),
        }
        builtin =std_functions .get (path )
        if builtin is None :
            return None 
        return traitmethodinfo (
        owner =builtin .owner ,
        generics =builtin .generics ,
        params =[self ._normalize_type (param )for param in builtin .params ],
        return_type =self ._normalize_type (builtin .return_type ),
        has_receiver =builtin .has_receiver ,
        receiver_mode =builtin .receiver_mode ,
        )

    def _normalize_type (self ,ty :type )->type :
        if isinstance (ty ,namedtype ):
            name =self .type_aliases .get (ty .name ,ty .name )
            return namedtype (name ,[self ._normalize_type (arg )for arg in ty .args ])
        if isinstance (ty ,referencetype ):
            return referencetype (self ._normalize_type (ty .inner ),mutable =ty .mutable )
        if isinstance (ty ,slicetype ):
            return slicetype (self ._normalize_type (ty .inner ))
        if isinstance (ty ,functiontype ):
            return functiontype (
            [self ._normalize_type (param )for param in ty .params ],
            self ._normalize_type (ty .return_type or unit ),
            )
        return ty 

    def _variant_name (self ,path :str )->str :
        if "::"in path :
            return path .split ("::")[-1 ]
        if "."in path :
            return path .split (".")[-1 ]
        return path 

    def _receiver_mode (self ,param :Optional [param ])->str :
        if param is None or param .name !="self":
            return "value"
        if param .type_name .startswith ("&mut "):
            return "mut_ref"
        if param .type_name .startswith ("&"):
            return "ref"
        return "value"

    def _validate_receiver (self ,method :traitmethodinfo ,receiver_type :type ,receiver_expr :expr ,method_name :str )->None :
        if not method .has_receiver :
            return 
        if method .receiver_mode =="mut_ref":
            if isinstance (receiver_type ,referencetype ):
                if not receiver_type .mutable :
                    self ._error (f"method {method_name } requires mutable receiver")
            elif not self ._can_auto_borrow_mut (receiver_expr ):
                self ._error (f"method {method_name } requires mutable receiver")
        elif method .receiver_mode =="ref":
            return 
        elif method .receiver_mode =="value":
            return 

    def _validate_builtin_receiver (
    self ,
    method ,
    receiver_type :type ,
    receiver_expr :expr ,
    method_name :str ,
    )->None :
        if self ._builtin_receiver_ok (method ,receiver_type ,receiver_expr ):
            return 
        if method .receiver_mode =="mut":
            self ._error (f"method {method_name } requires mutable receiver")

    def _builtin_receiver_ok (self ,method ,receiver_type :type ,receiver_expr :expr )->bool :
        if method .receiver_mode =="mut":
            if isinstance (receiver_type ,referencetype ):
                return receiver_type .mutable 
            if method .receiver_policy =="explicit_mut_ref":
                return False 
            return self ._can_auto_borrow_mut (receiver_expr )
        if method .receiver_mode =="ref":
            if isinstance (receiver_type ,referencetype ):
                return True 
            if method .receiver_policy in {"shared_or_addressable","addressable"}:
                return self ._can_auto_borrow_shared (receiver_expr )
        return True 

    def _clone_scope (self ,scope :Dict [str ,varstate ])->Dict [str ,varstate ]:
        return {name :varstate (**vars (state ))for name ,state in scope .items ()}

    def _merge_back (self ,dest :Dict [str ,varstate ],source :Dict [str ,varstate ])->None :
        for name ,state in source .items ():
            if name in dest :
                dest [name ]=varstate (**vars (state ))

    def _join_scopes (
    self ,
    dest :Dict [str ,varstate ],
    left :Dict [str ,varstate ],
    right :Dict [str ,varstate ],
    )->None :
        for name ,original in list(dest .items ()):
            l =left .get (name ,original )
            r =right .get (name ,original )
            dest [name ]=varstate (
            ty =l .ty ,
            moved =l .moved or r .moved ,
            shared_borrows =max (l .shared_borrows ,r .shared_borrows ),
            mut_borrowed =l .mut_borrowed or r .mut_borrowed ,
            )

    def _error (self ,message :str )->None :
        self .diagnostics .append (diagnostic (message =message ))

    def _can_auto_borrow_mut (self ,expr :expr )->bool :
        return isinstance (expr ,(nameexpr ,memberexpr ,indexexpr ))

    def _can_auto_borrow_shared (self ,expr :expr )->bool :
        return isinstance (expr ,(nameexpr ,memberexpr ,indexexpr ))
