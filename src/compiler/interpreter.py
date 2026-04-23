from __future__ import annotations 

from dataclasses import dataclass 
from pathlib import Path 
from typing import Any ,Dict ,List ,Tuple 

from compiler .ast import (
assignstmt ,
binaryexpr ,
blockexpr ,
boolexpr ,
cforstmt ,
callexpr ,
expr ,
exprstmt ,
functiondecl ,
ifexpr ,
incrementstmt ,
indexexpr ,
intexpr ,
letstmt ,
literalpattern ,
memberexpr ,
nameexpr ,
namepattern ,
pattern ,
returnstmt ,
sourcefile ,
stringexpr ,
structliteralexpr ,
switchexpr ,
unaryexpr ,
variantpattern ,
whileexpr ,
wildcardpattern ,
)
from compiler .interpreter_dispatch import dispatch_imported_call ,dispatch_special_call 
from compiler .parser import parse_source 


class interpretererror (Exception ):
    pass 


@dataclass 
class returnsignal (Exception ):
    value :Any 


class interpreter :
    def __init__ (self ,source :sourcefile )->None :
        self .source =source 
        self .functions ={
        item .sig .name :item 
        for item in source .items 
        if isinstance (item ,functiondecl )and item .body is not None 
        }
        self .imports ={use .alias or use .path .split (".")[-1 ]:use .path for use in source .uses }
        self .explicit_exit_code :int |None =None 
        self .argv :List [str ]=[]
        self ._package_cache :Dict [str ,interpreter ]={}

    def run_main (self )->int :
        if "main"in self .functions :
            entry ="main"
        elif "Main"in self .functions :
            entry ="Main"
        else :
            raise interpretererror ("entry function main not found")

        result =self .call_function (entry ,[])
        if self .explicit_exit_code is not None :
            return self .explicit_exit_code 
        if result is None :
            return 0 
        if isinstance (result ,bool ):
            return int (result )
        if isinstance (result ,int ):
            return result 
        raise interpretererror (f"entry function must return int32/unit, got {type (result ).__name__ }")

    def call_function (self ,name :str ,args :List [Any ])->Any :
        handled ,value =dispatch_special_call (self ,name ,args )
        if handled :
            return value 

        imported_path =self .imports .get (name )
        if imported_path is not None :
            handled ,value =dispatch_imported_call (self ,imported_path ,args )
            if handled :
                return value 
            return self ._call_imported_function (imported_path ,args )

        fn =self .functions .get (name )
        if fn is None :
            raise interpretererror (f"unknown function {name }")

        if len (args )!=len (fn .sig .params ):
            raise interpretererror (
            f"function {name } expects {len (fn .sig .params )} args, got {len (args )}"
            )

        env ={param .name :value for param ,value in zip (fn .sig .params ,args )}
        try :
            return self .eval_block (fn .body ,env )
        except returnsignal as signal :
            return signal .value 

    def _call_imported_function (self ,imported_path :str ,args :List [Any ])->Any :
        package_path ,func_name =imported_path .rsplit (".",1 )
        imported_interpreter =self ._load_imported_package (package_path )
        try :
            result =imported_interpreter .call_function (func_name ,args )
        except interpretererror as exc :
        # fallback: some packages expose `main` (lowercase) while callers
        # request `main` (capitalized). try the lowercase variant before
        # giving up to improve compatibility during bootstrap.
            msg =str (exc )
            if "unknown function"in msg :
                alt_name =func_name [0 ].lower ()+func_name [1 :]
                try :
                    result =imported_interpreter .call_function (alt_name ,args )
                except interpretererror :
                    raise 
            else :
                raise 
        if imported_interpreter .explicit_exit_code is not None :
            self .explicit_exit_code =imported_interpreter .explicit_exit_code 
        return result 

    def _load_imported_package (self ,package_path :str )->"interpreter":
        cached =self ._package_cache .get (package_path )
        if cached is not None :
            return cached 

        source_path =self ._source_path_for_package (package_path )
        if source_path is None :
            raise interpretererror (f"unknown imported package {package_path }")
        source_text =source_path .read_text ()
        source =parse_source (source_text )
        child =interpreter (source )
        child .argv =self .argv 
        child ._package_cache =self ._package_cache 
        self ._package_cache [package_path ]=child 
        return child 

    def _source_path_for_package (self ,package_path :str )->Path |None :
        root =Path (__file__ ).resolve ().parent .parent 
        if package_path =="compile.internal":
            return root /"cmd"/"compile"/"internal"/"main.s"
        if package_path .startswith ("compile.internal.tests."):
            tail =package_path .removeprefix ("compile.internal.tests.")
            return root /"cmd"/"compile"/"internal"/"tests"/f"{tail }.s"
        if package_path .startswith ("compile.internal."):
            tail =package_path .removeprefix ("compile.internal.")
            if tail in {
            "main",
            "prelude",
            "semantic",
            "mir",
            "ownership",
            "typesys",
            "golden",
            "borrow",
            "backend_elf64",
            }:
                return root /"cmd"/"compile"/"internal"/f"{tail }.s"
            parts =tail .split (".")
            if tail == "build.utils":
                return root / "cmd" / "compile" / "internal" / "build" / "utils.s"
            return root / "cmd" / "compile" / "internal" / Path(*parts) / f"{parts[-1]}.s"
        if package_path .startswith ("internal."):
            tail =package_path .removeprefix ("internal.")
            parts =tail .split (".")
            return root /"internal"/Path (*parts )/f"{parts [-1 ]}.s"
        if package_path .startswith ("std."):
            tail =package_path .removeprefix ("std.")
            if tail =="prelude":
                return root /"prelude"/"prelude.s"
            parts =tail .split (".")
            return root /Path (*parts )/f"{parts [-1 ]}.s"
        return None 

    def eval_block (self ,block :blockexpr |None ,env :Dict [str ,Any ])->Any :
        if block is None :
            return None 
        local =dict(env )
        return self ._eval_block_in_place (block ,local )

    def _eval_block_in_place (self ,block :blockexpr ,env :Dict [str ,Any ])->Any :
        for stmt in block .statements :
            self .eval_stmt (stmt ,env )
        if block .final_expr is not None :
            return self .eval_expr (block .final_expr ,env )
        return None 

    def eval_stmt (
    self ,
    stmt :letstmt |assignstmt |incrementstmt |cforstmt |returnstmt |exprstmt ,
    env :Dict [str ,Any ],
    )->None :
        if isinstance (stmt ,letstmt ):
            env [stmt .name ]=self .eval_expr (stmt .value ,env )
            return 
        if isinstance (stmt ,assignstmt ):
            if stmt .name not in env :
                raise interpretererror (f"unknown name {stmt .name }")
            env [stmt .name ]=self .eval_expr (stmt .value ,env )
            return 
        if isinstance (stmt ,incrementstmt ):
            if stmt .name not in env :
                raise interpretererror (f"unknown name {stmt .name }")
            env [stmt .name ]=int (env [stmt .name ])+1 
            return 
        if isinstance (stmt ,cforstmt ):
            loop_env =dict(env )
            self .eval_stmt (stmt .init ,loop_env )
            while self .eval_expr (stmt .condition ,loop_env ):
                self ._eval_block_in_place (stmt .body ,loop_env )
                self .eval_stmt (stmt .step ,loop_env )
            for name in list(env .keys ()):
                if name in loop_env :
                    env [name ]=loop_env [name ]
            return 
        if isinstance (stmt ,returnstmt ):
            value =self .eval_expr (stmt .value ,env )if stmt .value is not None else None 
            raise returnsignal (value )
        if isinstance (stmt ,exprstmt ):
            self .eval_expr (stmt .expr ,env )
            return 
        raise interpretererror (f"unsupported statement {type (stmt ).__name__ }")

    def eval_expr (self ,expr :expr |None ,env :Dict [str ,Any ])->Any :
        if expr is None :
            return None 
        if isinstance (expr ,intexpr ):
            return int (expr .value .replace ("_",""))
        if isinstance (expr ,stringexpr ):
            return self ._decode_string_literal (expr .value )
        if isinstance (expr ,boolexpr ):
            return expr .value 
        if isinstance (expr ,nameexpr ):
            if expr .name in env :
                return env [expr .name ]
            if expr .name =="none":
                return ("none",None )
            raise interpretererror (f"unknown name {expr .name }")
        if isinstance (expr ,callexpr ):
            constructed =self ._eval_type_constructor (expr .callee ,expr .args ,env )
            if constructed is not None :
                return constructed 
            if isinstance (expr .callee ,memberexpr ):
                receiver =self .eval_expr (expr .callee .target ,env )
                args =[self .eval_expr (arg ,env )for arg in expr .args ]
                return self .eval_method_call (receiver ,expr .callee .member ,args )
            callee =self .eval_callee (expr .callee )
            args =[self .eval_expr (arg ,env )for arg in expr .args ]
            return self .call_function (callee ,args )
        if isinstance (expr ,binaryexpr ):
            left =self .eval_expr (expr .left ,env )
            right =self .eval_expr (expr .right ,env )
            return self .eval_binary (expr .op ,left ,right )
        if isinstance (expr ,unaryexpr ):
            operand =self .eval_expr (expr .operand ,env )
            if expr .op =="!":
                return not bool (operand )
            raise interpretererror (f"unsupported unary operator {expr .op }")
        if isinstance (expr ,memberexpr ):
            target =self .eval_expr (expr .target ,env )
            if isinstance (target ,Dict ):
                return target .get (expr .member )
            raise interpretererror (f"unsupported member access {expr .member }")
        if isinstance (expr ,indexexpr ):
            target =self .eval_expr (expr .target ,env )
            index =self .eval_expr (expr .index ,env )
            return target [int (index )]
        if isinstance (expr ,ifexpr ):
            if self .eval_expr (expr .condition ,env ):
                return self ._eval_block_in_place (expr .then_branch ,env )
            if expr .else_branch is not None :
                if isinstance (expr .else_branch ,blockexpr ):
                    return self ._eval_block_in_place (expr .else_branch ,env )
                return self .eval_expr (expr .else_branch ,env )
            return None 
        if isinstance (expr ,whileexpr ):
            while self .eval_expr (expr .condition ,env ):
                self ._eval_block_in_place (expr .body ,env )
            return None 
        if isinstance (expr ,structliteralexpr ):
            value :Dict [str ,Any ]={}
            for field in expr .fields :
                value [field .name ]=self .eval_expr (field .value ,env )
            return value 
        if isinstance (expr ,switchexpr ):
            subject =self .eval_expr (expr .subject ,env )
            for arm in expr .arms :
                bindings =self ._match_pattern (arm .pattern ,subject )
                if bindings is None :
                    continue 
                arm_env =dict(env )
                arm_env .update (bindings )
                return self .eval_expr (arm .expr ,arm_env )
            return None 
        if isinstance (expr ,blockexpr ):
            return self .eval_block (expr ,env )
        raise interpretererror (f"unsupported expression {type (expr ).__name__ }")

    def eval_callee (self ,expr :expr )->str :
        if isinstance (expr ,nameexpr ):
            return expr .name 
        raise interpretererror (f"unsupported callee {type (expr ).__name__ }")

    def eval_method_call (self ,receiver :Any ,member :str ,args :List [Any ])->Any :
        if member =="push"and isinstance (receiver ,List ):
            if args :
                receiver .append (args [0 ])
            return None 
        if member =="len":
            return len (receiver )
        if isinstance (receiver ,Tuple )and len (receiver )==2 and receiver [0 ]in {"ok","err"}:
            tag ,payload =receiver 
            if member =="is_ok":
                return tag =="ok"
            if member =="is_err":
                return tag =="err"
            if member =="unwrap":
                if tag =="ok":
                    return payload 
                raise interpretererror ("called result.unwrap() on err")
            if member =="unwrap_err":
                if tag =="err":
                    return payload 
                raise interpretererror ("called result.unwrap_err() on ok")
        raise interpretererror (f"unsupported method {member }")

    def _eval_type_constructor (self ,callee :expr ,args :List [expr ],env :Dict [str ,Any ])->Any :
        if isinstance (callee ,indexexpr )and isinstance (callee .target ,nameexpr )and callee .target .name =="vec":
            return [self .eval_expr (arg ,env )for arg in args ]
        if isinstance (callee ,nameexpr )and callee .name =="vec":
            return [self .eval_expr (arg ,env )for arg in args ]
        return None 

    def _match_pattern (self ,pattern :pattern ,value :Any )->Dict [str ,Any ]|None :
        if isinstance (pattern ,wildcardpattern ):
            return {}
        if isinstance (pattern ,namepattern ):
            return {pattern .name :value }
        if isinstance (pattern ,literalpattern ):
            literal =pattern .value 
            if isinstance (literal ,intexpr ):
                return {}if int (literal .value .replace ("_",""))==value else None 
            if isinstance (literal ,stringexpr ):
                return {}if self ._decode_string_literal (literal .value )==value else None 
            if isinstance (literal ,boolexpr ):
                return {}if literal .value ==value else None 
            return None 
        if isinstance (pattern ,variantpattern ):
            tag =pattern .path .split ("::")[-1 ].split (".")[-1 ]
            if not isinstance (value ,Tuple )or len (value )!=2 or value [0 ]!=tag :
                return None 
            payload =value [1 ]
            if not pattern .args :
                return {}
            bindings :Dict [str ,Any ]={}
            for arg in pattern .args :
                matched =self ._match_pattern (arg ,payload )
                if matched is None :
                    return None 
                bindings .update (matched )
            return bindings 
        return None 

    def eval_binary (self ,op :str ,left :Any ,right :Any )->Any :
        if op =="+":
            return left +right 
        if op =="-":
            return left -right 
        if op =="*":
            return left *right 
        if op =="/":
            return left //right 
        if op =="==":
            return left ==right 
        if op =="!=":
            return left !=right 
        if op =="<":
            return left <right 
        if op =="<=":
            return left <=right 
        if op ==">":
            return left >right 
        if op ==">=":
            return left >=right 
        if op =="&&":
            return bool (left )and bool (right )
        if op =="||":
            return bool (left )or bool (right )
        raise interpretererror (f"unsupported binary operator {op }")

    def _stringify (self ,value :Any )->str :
        if value is None :
            return "()"
        if isinstance (value ,Tuple )and len (value )==2 :
            if value [0 ]=="none":
                return "none"
            return f"{value [0 ]}({self ._stringify (value [1 ])})"
        if value is True :
            return "true"
        if value is False :
            return "false"
        return str (value )

    def _decode_string_literal (self ,literal :str )->str :
        text =literal [1 :-1 ]
        out :List [str ]=[]
        index =0 
        while index <len (text ):
            ch =text [index ]
            if ch !="\\":
                out .append (ch )
                index +=1 
                continue 
            if index +1 >=len (text ):
                out .append ("\\")
                break 
            esc =text [index +1 ]
            if esc =="n":
                out .append ("\n")
            elif esc =="t":
                out .append ("\t")
            elif esc =='"':
                out .append ('"')
            elif esc =="\\":
                out .append ("\\")
            else :
                out .append (esc )
            index +=2 
        return "".join (out )
