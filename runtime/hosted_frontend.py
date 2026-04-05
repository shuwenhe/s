from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from compiler.ast import dump_source_file
from compiler.lexer.tokens import KEYWORDS, Token, TokenKind, dump_tokens
from compiler.parser.parser import Parser
from runtime.intrinsic_dispatch import IntrinsicCall, dispatch


@dataclass
class HostedLexError(Exception):
    message: str
    line: int
    column: int

    def __str__(self) -> str:
        return f"{self.message} at {self.line}:{self.column}"


@dataclass
class HostedLexer:
    source: str
    trace: list[IntrinsicCall] = field(default_factory=list)
    index: int = 0
    line: int = 1
    column: int = 1

    def tokenize(self) -> list[Token]:
        tokens: list[Token] = []
        while not self.is_eof():
            self.skip_ignored()
            if self.is_eof():
                break
            start_line = self.line
            start_col = self.column
            ch = self.peek()
            if ch.isalpha() or ch == "_":
                value = self.read_identifier()
                kind = TokenKind.KEYWORD if value in KEYWORDS else TokenKind.IDENT
                tokens.append(Token(kind, value, start_line, start_col))
                continue
            if ch.isdigit():
                tokens.append(Token(TokenKind.INT, self.read_number(), start_line, start_col))
                continue
            if ch == '"':
                tokens.append(Token(TokenKind.STRING, self.read_string(), start_line, start_col))
                continue
            tokens.append(Token(TokenKind.SYMBOL, self.read_symbol(), start_line, start_col))
        tokens.append(Token(TokenKind.EOF, "<eof>", self.line, self.column))
        return tokens

    def skip_ignored(self) -> None:
        while not self.is_eof():
            ch = self.peek()
            if ch in " \t\r\n":
                self.advance()
                continue
            if self.match_text("//"):
                while not self.is_eof() and self.peek() != "\n":
                    self.advance()
                continue
            if self.match_text("/*"):
                self.advance()
                self.advance()
                depth = 1
                while depth > 0:
                    if self.is_eof():
                        raise HostedLexError("unterminated block comment", self.line, self.column)
                    if self.match_text("/*"):
                        depth += 1
                        self.advance()
                        self.advance()
                        continue
                    if self.match_text("*/"):
                        depth -= 1
                        self.advance()
                        self.advance()
                        continue
                    self.advance()
                continue
            break

    def read_identifier(self) -> str:
        chars: list[str] = []
        while not self.is_eof():
            ch = self.peek()
            if not (ch.isalnum() or ch == "_"):
                break
            chars.append(self.advance())
        return "".join(chars)

    def read_number(self) -> str:
        chars: list[str] = []
        while not self.is_eof():
            ch = self.peek()
            if not ch.isdigit():
                break
            chars.append(self.advance())
        return "".join(chars)

    def read_string(self) -> str:
        out = [self.advance()]
        while not self.is_eof():
            ch = self.advance()
            out.append(ch)
            if ch == "\\":
                if self.is_eof():
                    raise HostedLexError("unterminated escape sequence", self.line, self.column)
                out.append(self.advance())
                continue
            if ch == '"':
                return "".join(out)
        raise HostedLexError("unterminated string literal", self.line, self.column)

    def read_symbol(self) -> str:
        for symbol in ("->", "=>", "==", "!=", "<=", ">=", "&&", "||", "..=", ".."):
            if self.match_text(symbol):
                out = []
                for _ in symbol:
                    out.append(self.advance())
                return "".join(out)
        ch = self.peek()
        if ch in "()[]{}.,:;+-*/%!=<>?&|":
            return self.advance()
        raise HostedLexError(f"unexpected character {ch!r}", self.line, self.column)

    def match_text(self, text: str) -> bool:
        return self._slice(self.index, self.index + self._len(text)) == text

    def peek(self) -> str:
        if self.is_eof():
            raise HostedLexError("unexpected eof", self.line, self.column)
        return self._char_at(self.index)

    def advance(self) -> str:
        if self.is_eof():
            raise HostedLexError("unexpected eof", self.line, self.column)
        ch = self._char_at(self.index)
        self.index += 1
        if ch == "\n":
            self.line += 1
            self.column = 1
        else:
            self.column += 1
        return ch

    def is_eof(self) -> bool:
        return self.index >= self._len(self.source)

    def _len(self, value: object) -> int:
        call = IntrinsicCall(symbol="__runtime_len", args=(value,), source="HostedLexer")
        self.trace.append(call)
        return dispatch(call).value

    def _char_at(self, index: int) -> str:
        call = IntrinsicCall(
            symbol="__string_char_at",
            args=(self.source, index),
            source="HostedLexer",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _slice(self, start: int, end: int) -> str:
        call = IntrinsicCall(
            symbol="__string_slice",
            args=(self.source, start, end),
            source="HostedLexer",
        )
        self.trace.append(call)
        return dispatch(call).value


@dataclass(frozen=True)
class PlanStep:
    kind: str
    detail: str


@dataclass
class ExecutionPlan:
    name: str
    path: Path
    steps: list[PlanStep] = field(default_factory=list)
    intrinsic_calls: list[IntrinsicCall] = field(default_factory=list)


@dataclass
class ExecutionResult:
    output: str
    plan: ExecutionPlan


def run_lex_dump(path: Path) -> ExecutionResult:
    source = path.read_text()
    plan = ExecutionPlan(name="lex_dump", path=path)
    plan.steps.append(PlanStep("read_source", str(path)))
    lexer = HostedLexer(source)
    tokens = lexer.tokenize()
    plan.steps.append(PlanStep("tokenize", f"{len(tokens)} tokens"))
    plan.steps.append(PlanStep("dump_tokens", "render token stream"))
    plan.intrinsic_calls.extend(lexer.trace)
    return ExecutionResult(output=dump_tokens(tokens), plan=plan)


def run_ast_dump(path: Path) -> ExecutionResult:
    source = path.read_text()
    plan = ExecutionPlan(name="ast_dump", path=path)
    plan.steps.append(PlanStep("read_source", str(path)))
    lexer = HostedLexer(source)
    tokens = lexer.tokenize()
    plan.steps.append(PlanStep("tokenize", f"{len(tokens)} tokens"))
    ast = Parser(tokens).parse_source_file()
    plan.steps.append(PlanStep("parse_source_file", "build SourceFile AST"))
    plan.steps.append(PlanStep("dump_source_file", "render AST dump"))
    plan.intrinsic_calls.extend(lexer.trace)
    return ExecutionResult(output=dump_source_file(ast), plan=plan)
