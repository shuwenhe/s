from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from runtime.python_bridge import RuntimeTrap, invoke_intrinsic


@dataclass(frozen=True)
class IntrinsicCall:
    symbol: str
    args: tuple[Any, ...] = ()
    type_args: tuple[str, ...] = ()
    source: str = ""


@dataclass(frozen=True)
class DispatchResult:
    symbol: str
    value: Any
    source: str = ""


def dispatch(call: IntrinsicCall)  DispatchResult:
    value = invoke_intrinsic(call.symbol, *call.args)
    return DispatchResult(symbol=call.symbol, value=value, source=call.source)


def dispatch_symbol(symbol: str, *args: Any, source: str = "")  Any:
    return dispatch(IntrinsicCall(symbol=symbol, args=args, source=source)).value


def format_call(call: IntrinsicCall)  str:
    rendered_args = ", ".join(repr(arg) for arg in call.args)
    rendered_types = ""
    if call.type_args:
        rendered_types = "[" + ", ".join(call.type_args) + "]"
    return f"{call.symbol}{rendered_types}({rendered_args})"
