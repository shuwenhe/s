from __future__ import annotations 

from dataclasses import dataclass ,field as datfield 
import json 
from pathlib import Path 
from typing import Dict ,List ,Optional ,Optional 

from compiler.typesys import functiontype, slicetype, type, unit, namedtype, parse_type


@dataclass (frozen =True )
class builtinmethoddecl :
    name :str 
    trait_name :str |None 
    receiver_mode :str 
    signature :functiontype 
    receiver_policy :str ="addressable"


@dataclass (frozen =True )
class builtinfielddecl :
    name :str 
    ty :type 
    visibility :str 
    readable :bool =True 
    writable :bool =False 


@dataclass (frozen =True )
class builtintraitdecl :
    name :str 
    methods :Dict [str ,Tuple [builtinmethoddecl ,...]]=datfield(default_factory=dict)


@dataclass (frozen =True )
class builtintypedecl :
    name :str 
    traits :Tuple [str ,...]=()
    fields :Dict [str ,builtinfielddecl ]=datfield(default_factory=dict)
    methods :Dict [str ,Tuple [builtinmethoddecl ,...]]=datfield(default_factory=dict)
    index_result_kind :Optional [str ]=None 
    default_impls :Tuple [str ,...]=()


@dataclass (frozen =True )
class builtinmoduledecl :
    name :str 
    traits :Dict [str ,builtintraitdecl ]=datfield(default_factory=dict)
    types :Dict [str ,builtintypedecl ]=datfield(default_factory=dict)


def load_prelude ()->builtinmoduledecl :
    path = Path(__file__).resolve().parent / "builtins" / "prelude.json"
    data = json.loads(path.read_text())
    traits :Dict [str ,builtintraitdecl ]={}
    for trait_name ,trait_data in data .get ("traits",{}).items ():
        methods :Dict [str ,Tuple [builtinmethoddecl ,...]]={}
        for method_name ,method_data in trait_data .get ("methods",{}).items ():
            methods [method_name ]=_load_overloads (method_name ,method_data )
        traits [trait_name ]=builtintraitdecl (name =trait_name ,methods =methods )
    types :Dict [str ,builtintypedecl ]={}
    for type_name ,type_data in data ["types"].items ():
        methods :Dict [str ,Tuple [builtinmethoddecl ,...]]={}
        for method_name ,method_data in type_data .get ("methods",{}).items ():
            methods [method_name ]=_load_overloads (method_name ,method_data )
        fields ={
        field_name :builtinfielddecl (
        name =field_name ,
        ty =parse_type (field_data ["type"]),
        visibility =field_data .get ("visibility","priv"),
        readable =field_data .get ("readable",True ),
        writable =field_data .get ("writable",False ),
        )
        for field_name ,field_data in type_data .get ("fields",{}).items ()
        }
        index_info =type_data .get ("index")
        types [type_name ]=builtintypedecl (
        name =type_name ,
        traits =tuple(type_data .get ("traits",[])),
        fields =fields ,
        methods =methods ,
        index_result_kind =index_info .get ("result_kind")if index_info else None ,
        default_impls =tuple(type_data .get ("default_impls",[])),
        )
    return builtinmoduledecl (name =data ["module"],traits =traits ,types =types )


def _load_overloads (method_name :str ,method_data :Dict )->Tuple [builtinmethoddecl ,...]:
    overloads =method_data .get ("overloads")
    if overloads is None :
        overloads =[method_data ]
    return tuple(_build_method (method_name ,overload )for overload in overloads )


def _build_method (method_name :str ,method_data :Dict )->builtinmethoddecl :
    params =[parse_type (param )for param in method_data .get ("params",[])]
    return builtinmethoddecl (
    name =method_name ,
    trait_name =method_data .get ("trait"),
    receiver_mode =method_data ["receiver_mode"],
    receiver_policy =method_data .get ("receiver_policy","addressable"),
    signature =functiontype (params ,parse_type (method_data .get ("return_type","()"))),
    )


prelude =load_prelude ()


def lookup_builtin_type (receiver_type :type )->Optional [builtintypedecl ]:
    base =_base_name (receiver_type )
    if base is None :
        return None 
    return prelude .types .get (base )


def lookup_builtin_methods (receiver_type :type ,member :str )->Tuple [builtinmethoddecl ,...]:
    builtin_type =lookup_builtin_type (receiver_type )
    if builtin_type is None :
        return ()
    methods =builtin_type .methods .get (member ,())
    if builtin_type .name =="vec"and member =="push":
        inner =_unwrap_refs (receiver_type )
        if isinstance (inner ,namedtype )and inner .args :
            rewritten =[]
            for method in methods :
                params =list(method .signature .params )
                if params and isinstance (params [0 ],namedtype )and params [0 ].name =="t":
                    params [0 ]=inner .args [0 ]
                rewritten .append (
                builtinmethoddecl (
                name =method .name ,
                trait_name =method .trait_name ,
                receiver_mode =method .receiver_mode ,
                receiver_policy =method .receiver_policy ,
                signature =functiontype (params ,method .signature .return_type or unit ),
                )
                )
            return tuple(rewritten )
    if builtin_type .name =="result":
        inner =_unwrap_refs (receiver_type )
        if isinstance (inner ,namedtype )and len (inner .args )>=2 :
            ok_type =inner .args [0 ]
            err_type =inner .args [1 ]
            rewritten =[]
            for method in methods :
                params =[
                ok_type if isinstance (param ,namedtype )and param .name =="t"else 
                err_type if isinstance (param ,namedtype )and param .name =="e"else 
                param 
                for param in method .signature .params 
                ]
                return_type =method .signature .return_type 
                if isinstance (return_type ,namedtype )and return_type .name =="t":
                    return_type =ok_type 
                elif isinstance (return_type ,namedtype )and return_type .name =="e":
                    return_type =err_type 
                rewritten .append (
                builtinmethoddecl (
                name =method .name ,
                trait_name =method .trait_name ,
                receiver_mode =method .receiver_mode ,
                receiver_policy =method .receiver_policy ,
                signature =functiontype (params ,return_type or unit ),
                )
                )
            return tuple(rewritten )
    return methods 


def lookup_builtin_method (receiver_type :type ,member :str )->Optional [builtinmethoddecl ]:
    methods =lookup_builtin_methods (receiver_type ,member )
    if len (methods )==1 :
        return methods [0 ]
    return None 


def lookup_index_type (receiver_type :type )->Optional [type ]:
    inner =_unwrap_refs (receiver_type )
    builtin_type =lookup_builtin_type (inner )
    if builtin_type is not None and builtin_type .index_result_kind =="first_type_arg":
        if isinstance (inner ,namedtype )and inner .args :
            return inner .args [0 ]
    if isinstance (inner ,slicetype ):
        return inner .inner 
    return None 


def _unwrap_refs (ty :type )->type :
    from compiler .typesys import referencetype 

    while isinstance (ty ,referencetype ):
        ty =ty .inner 
    return ty 


def _base_name (ty :type )->Optional [str ]:
    inner =_unwrap_refs (ty )
    if isinstance (inner ,namedtype ):
        return inner .name 
    return None 
