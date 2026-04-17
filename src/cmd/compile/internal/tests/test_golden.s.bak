package compile.internal.tests.testGolden

use std.fs.ReadToString
use std.io.println
use compile.internal.syntax.ReadSource
use compile.internal.syntax.Tokenize
use compile.internal.syntax.DumpTokensText

func RunGoldenSuite(string fixturesRoot) int32 {
    // Expect fixturesRoot to contain sample.s and sample.tokens
    var sourcePath = fixturesRoot + "/sample.s"
    var tokensPath = fixturesRoot + "/sample.tokens"

    var sourceResult = ReadSource(sourcePath)
    if sourceResult.isErr() {
        println("failed to read sample.s");
        return 1
    }

    var tokenResult = Tokenize(sourceResult.unwrap())
    if tokenResult.isErr() {
        println("lexer error");
        return 1
    }

    var actual = DumpTokensText(tokenResult.unwrap())

    var expectedResult = ReadToString(tokensPath)
    if expectedResult.isErr() {
        println("failed to read sample.tokens");
        return 1
    }

    var expected = expectedResult.unwrap()
    if actual == expected {
        println("lexDump: OK");
        return 0
    }
    println("lexDump: MISMATCH");
    println("--- expected ---");
    println(expected);
    println("--- actual ---");
    println(actual);
    2
}
