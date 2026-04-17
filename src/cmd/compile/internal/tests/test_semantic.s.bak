package compile.internal.tests.testSemantic

use compile.internal.semantic.CheckText
use std.fs.ReadToString

func RunSemanticSuite(string fixturesRoot) int32 {
    var okPath = fixturesRoot + "/checkOk.s"
    var failPath = fixturesRoot + "/checkFail.s"

    var okSourceResult = ReadToString(okPath)
    if okSourceResult.isErr() {
        return 1
    }
    var failSourceResult = ReadToString(failPath)
    if failSourceResult.isErr() {
        return 1
    }

    if CheckText(okSourceResult.unwrap()) != 0 {
        return 1
    }
    if CheckText(failSourceResult.unwrap()) == 0 {
        return 1
    }

    var inlineOk = "package demo.inline\nfunc add(int32 a, int32 b) int32 {\n    var sum: int32 = a + b\n    sum\n}"
    if CheckText(inlineOk) != 0 {
        return 1
    }

    var inlineFail = "package demo.inline\nfunc broken() bool {\n    var flag: bool = 1\n    flag\n}"
    if CheckText(inlineFail) == 0 {
        return 1
    }

    var callOk = "package demo.call\nfunc add(int32 a, int32 b) int32 {\n  a + b\n}\nfunc main() int32 {\n  add(1, 2)\n}"
    if CheckText(callOk) != 0 {
        return 1
    }

    var callFail = "package demo.call\nfunc add(int32 a, int32 b) int32 {\n  a + b\n}\nfunc main() int32 {\n  add(1, true)\n}"
    if CheckText(callFail) == 0 {
        return 1
    }

    var callUndefinedFail = "package demo.call\nfunc main() int32 {\n  missing(1)\n}"
    if CheckText(callUndefinedFail) == 0 {
        return 1
    }

    var overloadOk = "package demo.call\nfunc f[T](T v) T {\n  v\n}\nfunc f(int32 v) int32 {\n  v + 1\n}\nfunc main() int32 {\n  f(1)\n}"
    if CheckText(overloadOk) != 0 {
        return 1
    }

    var overloadGenericOk = "package demo.call\nfunc pick[T](T a, T b) T {\n  a\n}\nfunc main() int32 {\n  pick(1, 2)\n}"
    if CheckText(overloadGenericOk) != 0 {
        return 1
    }

    var overloadGenericFail = "package demo.call\nfunc pick[T](T a, T b) T {\n  a\n}\nfunc main() int32 {\n  pick(1, true)\n}"
    if CheckText(overloadGenericFail) == 0 {
        return 1
    }

    var overloadAmbiguousFail = "package demo.call\nfunc g[T](T v) T {\n  v\n}\nfunc g[U](U v) U {\n  v\n}\nfunc main() int32 {\n  g(1)\n}"
    if CheckText(overloadAmbiguousFail) == 0 {
        return 1
    }

    var optionMatchOk = "package demo.match\nfunc f(Option[int32] value) int32 {\n  match value {\n    Some(v) => v,\n    None => 0,\n  }\n}"
    if CheckText(optionMatchOk) != 0 {
        return 1
    }

    var optionMatchExhaustFail = "package demo.match\nfunc f(Option[int32] value) int32 {\n  match value {\n    Some(v) => v,\n  }\n}"
    if CheckText(optionMatchExhaustFail) == 0 {
        return 1
    }

    var optionMatchDuplicateFail = "package demo.match\nfunc f(Option[int32] value) int32 {\n  match value {\n    Some(v) => v,\n    Some(w) => w,\n    None => 0,\n  }\n}"
    if CheckText(optionMatchDuplicateFail) == 0 {
        return 1
    }

    var optionMatchUnreachableFail = "package demo.match\nfunc f(Option[int32] value) int32 {\n  match value {\n    _ => 0,\n    Some(v) => v,\n  }\n}"
    if CheckText(optionMatchUnreachableFail) == 0 {
        return 1
    }

    var optionMatchBindTypeFail = "package demo.match\nfunc f(Option[int32] value) bool {\n  match value {\n    Some(v) => v,\n    None => false,\n  }\n}"
    if CheckText(optionMatchBindTypeFail) == 0 {
        return 1
    }

    var resultMatchOk = "package demo.match\nfunc f(Result[int32, string] value) int32 {\n  match value {\n    Ok(v) => v,\n    Err(e) => 0,\n  }\n}"
    if CheckText(resultMatchOk) != 0 {
        return 1
    }

    var resultMatchExhaustFail = "package demo.match\nfunc f(Result[int32, string] value) int32 {\n  match value {\n    Ok(v) => v,\n  }\n}"
    if CheckText(resultMatchExhaustFail) == 0 {
        return 1
    }

    var resultMatchDuplicateFail = "package demo.match\nfunc f(Result[int32, string] value) int32 {\n  match value {\n    Ok(v) => v,\n    Err(e) => 0,\n    Err(e2) => 1,\n  }\n}"
    if CheckText(resultMatchDuplicateFail) == 0 {
        return 1
    }

    var optionNestedPayloadFail = "package demo.match\nfunc f(Option[int32] value) int32 {\n  match value {\n    Some(Ok(v)) => v,\n    None => 0,\n  }\n}"
    if CheckText(optionNestedPayloadFail) == 0 {
        return 1
    }

    var nestedOk = "package demo.match\nfunc f(Option[Result[int32, string]] value) int32 {\n  match value {\n    Some(Ok(v)) => v,\n    Some(Err(e)) => 0,\n    None => 0,\n  }\n}"
    if CheckText(nestedOk) != 0 {
        return 1
    }

    0
}
