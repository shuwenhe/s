from .types import *


def check_source(source):
    from .check import check_source as impl

    return impl(source)


def __getattr__(name: str):
    if name in {"CheckResult", "Diagnostic"}:
        from . import check as check_module

        return getattr(check_module, name)
    raise AttributeError(name)
