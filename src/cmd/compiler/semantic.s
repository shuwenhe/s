package compiler

use compiler.internal.typecheck.CheckResult
use compiler.internal.typecheck.CheckSource as InternalCheckSource

func CheckSource(s.SourceFile source) -> CheckResult {
    InternalCheckSource(source)
}

func IsOK(CheckResult result) -> bool {
    result.diagnostics.len() == 0
}
