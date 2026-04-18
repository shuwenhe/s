from __future__ import annotations 

from dataclasses import dataclass 
from typing import Dict, Dict 

from compiler.typesys import type ,is_copy_type 


@dataclass (frozen =True )
class ownershipdecision :
    ty :type 
    copyable :bool 
    droppable :bool 


def make_decision (ty :type )->ownershipdecision :
    copyable =is_copy_type (ty )
    return ownershipdecision (ty =ty ,copyable =copyable ,droppable =not copyable )


def make_plan (type_env :Dict [str ,type ])->Dict [str ,ownershipdecision ]:
    return {name :make_decision (ty )for name ,ty in type_env .items ()}
