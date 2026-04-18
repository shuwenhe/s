from __future__ import annotations 

from dataclasses import dataclass ,field as datfield 
from typing import Dict ,List ,List 


class type :
    pass 


@dataclass (frozen =True )
class primitivetype (type ):
    name :str 


@dataclass (frozen =True )
class namedtype (type ):
    name :str 
    args :List [type ]=datfield(default_factory=list)


@dataclass (frozen =True )
class referencetype (type ):
    inner :type 
    mutable :bool =False 


@dataclass (frozen =True )
class slicetype (type ):
    inner :type 


@dataclass (frozen =True )
class functiontype (type ):
    params :List [type ]=datfield(default_factory=list)
    return_type :type |None =None 


@dataclass (frozen =True )
class unittype (type ):
    pass 


@dataclass (frozen =True )
class nevertype (type ):
    pass 


@dataclass (frozen =True )
class unknowntype (type ):
    label :str ="unknown"


bool =primitivetype ("bool")
i32 =primitivetype ("int32")
string =namedtype ("string")
unit =unittype ()
never =nevertype ()


def parse_type (text :str )->type :
    text =text .strip ()
    if not text :
        return unknowntype ()
    if text =="()":
        return unit 
    if text =="never":
        return never 
    if text =="bool":
        return bool 
    if text in {"int32","int32","int"}:
        return i32 
    if text in {"string","string"}:
        return string 
    if text .startswith ("&mut "):
        return referencetype (parse_type (text [5 :].strip ()),mutable =True )
    if text .startswith ("&"):
        return referencetype (parse_type (text [1 :].strip ()),mutable =False )
    if text .startswith ("[]"):
        return slicetype (parse_type (text [2 :].strip ()))
    if "["in text and text .endswith ("]"):
        name ,args_text =text .split ("[",1 )
        inner =args_text [:-1 ]
        args =[_part for _part in _split_args (inner )if _part ]
        return namedtype (name .strip (),[parse_type (arg )for arg in args ])
    return namedtype (text )


def dump_type (ty :type )->str :
    if isinstance (ty ,primitivetype ):
        return ty .name 
    if isinstance (ty ,namedtype ):
        if not ty .args :
            return ty .name 
        return f"{ty .name }[{', '.join (dump_type (arg )for arg in ty .args )}]"
    if isinstance (ty ,referencetype ):
        prefix ="&mut "if ty .mutable else "&"
        return prefix +dump_type (ty .inner )
    if isinstance (ty ,slicetype ):
        return "[]"+dump_type (ty .inner )
    if isinstance (ty ,functiontype ):
        return f"func({', '.join (dump_type (param )for param in ty .params )}) {dump_type (ty .return_type or unit )}"
    if isinstance (ty ,unittype ):
        return "()"
    if isinstance (ty ,nevertype ):
        return "never"
    if isinstance (ty ,unknowntype ):
        return ty .label 
    return repr (ty )


def is_copy_type (ty :type )->bool :
    if isinstance (ty ,primitivetype ):
        return True 
    if isinstance (ty ,referencetype ):
        return True 
    if isinstance (ty ,nevertype ):
        return True 
    return False 


def substitute_type (ty :type ,mapping :Dict [str ,type ])->type :
    if isinstance (ty ,namedtype )and not ty .args and ty .name in mapping :
        return mapping [ty .name ]
    if isinstance (ty ,namedtype ):
        return namedtype (ty .name ,[substitute_type (arg ,mapping )for arg in ty .args ])
    if isinstance (ty ,referencetype ):
        return referencetype (substitute_type (ty .inner ,mapping ),mutable =ty .mutable )
    if isinstance (ty ,slicetype ):
        return slicetype (substitute_type (ty .inner ,mapping ))
    if isinstance (ty ,functiontype ):
        return functiontype (
        [substitute_type (param ,mapping )for param in ty .params ],
        substitute_type (ty .return_type or unit ,mapping ),
        )
    return ty 


def _split_args (text :str )->List [str ]:
    parts :List [str ]=[]
    current :List [str ]=[]
    depth =0 
    for ch in text :
        if ch =="[":
            depth +=1 
        elif ch =="]":
            depth -=1 
        if ch ==","and depth ==0 :
            parts .append ("".join (current ).strip ())
            current =[]
            continue 
        current .append (ch )
    if current :
        parts .append ("".join (current ).strip ())
    return parts 
