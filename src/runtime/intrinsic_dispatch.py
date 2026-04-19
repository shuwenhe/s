from __future__ import annotations

from dataclasses import dataclass, field

from runtime.compat import *
from runtime.python_bridge import runtimetrap, invoke_intrinsic


@dataclass(frozen=true)
class intrinsiccall:
    symbol: str
    args: tuple[any, ...] = ()
    type_args: tuple[str, ...] = ()
    source: str = ""


@dataclass(frozen=true)
class dispatchresult:
    symbol: str
    value: any
    source: str = ""


def dispatch(call: intrinsiccall) -> dispatchresult:
    value = invoke_intrinsic(call.symbol, *call.args)
    return dispatchresult(symbol=call.symbol, value=value, source=call.source)


def dispatch_symbol(symbol: str, *args: any, source: str = "") -> any:
    return dispatch(intrinsiccall(symbol=symbol, args=args, source=source)).value


def format_call(call: intrinsiccall) -> str:
    rendered_args = ", ".join(repr(arg) for arg in call.args)
    rendered_types = ""
    if call.type_args:
        rendered_types = "[" + ", ".join(call.type_args) + "]"
    return f"{call.symbol}{rendered_types}({rendered_args})"
