from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from compiler.ast import NamePattern, VariantPattern, WildcardPattern, dump_source_file
from compiler.lexer.tokens import KEYWORDS, Token, TokenKind, dump_tokens
from compiler.parser.parser import ParseError, Parser
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


@dataclass
class HostedParser(Parser):
    trace: list[IntrinsicCall] = field(default_factory=list)

    def _parse_pattern(self):
        if self._eat_ident_value("_"):
            return WildcardPattern()
        path = self._parse_path()
        if self._eat_symbol("("):
            args = []
            if not self._at_symbol(")"):
                while True:
                    args.append(self._parse_pattern())
                    if not self._eat_symbol(","):
                        break
                    if self._at_symbol(")"):
                        break
            self._expect_symbol(")")
            return VariantPattern(path=path, args=args)
        if self._path_contains_dot(path) or self._starts_with_upper(path):
            return VariantPattern(path=path)
        return NamePattern(name=path)

    def _parse_use_path(self) -> str:
        parts = [self._expect_ident()]
        while self._eat_symbol("."):
            if self._eat_symbol("{"):
                members: list[str] = []
                while not self._eat_symbol("}"):
                    member = self._expect_ident()
                    if self._eat_keyword("as"):
                        member = self._concat(member, self._concat(" as ", self._expect_ident()))
                    members.append(member)
                    self._eat_symbol(",")
                return self._concat(
                    self._concat(self._join_strings(parts, "."), ".{"),
                    self._concat(self._join_strings(members, ", "), "}"),
                )
            parts.append(self._expect_ident())
        return self._join_strings(parts, ".")

    def _parse_path(self) -> str:
        parts = [self._expect_ident()]
        while self._eat_symbol("."):
            parts.append(self._expect_ident())
        if self._at_symbol("["):
            last = parts.pop()
            parts.append(self._concat(last, self._parse_bracket_group()))
        return self._join_strings(parts, ".")

    def _expect_keyword(self, value: str):
        token = self._peek()
        if token.kind == TokenKind.KEYWORD and token.value == value:
            return self._advance()
        raise self._make_error(self._concat("expected keyword ", value), token.line, token.column)

    def _expect_symbol(self, value: str):
        token = self._peek()
        if token.kind == TokenKind.SYMBOL and token.value == value:
            return self._advance()
        raise self._make_error(self._concat("expected symbol ", value), token.line, token.column)

    def _expect_ident(self) -> str:
        token = self._peek()
        if token.kind == TokenKind.IDENT:
            self._advance()
            return token.value
        if token.kind == TokenKind.KEYWORD and token.value == "self":
            self._advance()
            return token.value
        raise self._make_error("expected identifier", token.line, token.column)

    def _path_contains_dot(self, path: str) -> bool:
        i = 0
        while i < self._len(path):
            if self._char_at(path, i) == ".":
                return True
            i += 1
        return False

    def _starts_with_upper(self, text: str) -> bool:
        if text == "":
            return False
        ch = self._char_at(text, 0)
        return "A" <= ch <= "Z"

    def _parse_type_text(self, stop_values: set[str]) -> str:
        parts: list[str] = []
        bracket = 0
        paren = 0

        while True:
            token = self._peek()
            if token.kind == TokenKind.EOF:
                break
            if bracket == 0 and paren == 0 and token.value in stop_values:
                break
            if token.value == "[":
                bracket += 1
            elif token.value == "]":
                bracket -= 1
            elif token.value == "(":
                paren += 1
            elif token.value == ")":
                if paren == 0:
                    break
                paren -= 1
            parts.append(self._advance().value)

        return self._normalize_type_text(self._join_strings(parts, " "))

    def _parse_bracket_group(self) -> str:
        parts = [self._advance().value]
        depth = 1
        while depth > 0:
            token = self._advance()
            parts.append(token.value)
            if token.value == "[":
                depth += 1
            elif token.value == "]":
                depth -= 1
        text = self._join_strings(parts, " ")
        text = self._replace(text, "[ ", "[")
        text = self._replace(text, " ]", "]")
        text = self._replace(text, " ,", ",")
        return text

    def _normalize_type_text(self, text: str) -> str:
        text = self._replace(text, " . ", ".")
        text = self._replace(text, "[ ", "[")
        text = self._replace(text, " ]", "]")
        text = self._replace(text, "( ", "(")
        text = self._replace(text, " )", ")")
        text = self._replace(text, " ,", ",")
        text = self._replace(text, "& mut ", "&mut ")
        text = self._replace(text, "[] ", "[]")
        text = self._replace(text, " [", "[")
        return text

    def _join_strings(self, values: list[str], sep: str) -> str:
        out = ""
        first = True
        for value in values:
            if not first:
                out = self._concat(out, sep)
            out = self._concat(out, value)
            first = False
        return out

    def _len(self, value: object) -> int:
        call = IntrinsicCall(symbol="__runtime_len", args=(value,), source="HostedParser")
        self.trace.append(call)
        return dispatch(call).value

    def _char_at(self, text: str, index: int) -> str:
        call = IntrinsicCall(
            symbol="__string_char_at",
            args=(text, index),
            source="HostedParser",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _concat(self, left: str, right: str) -> str:
        call = IntrinsicCall(
            symbol="__string_concat",
            args=(left, right),
            source="HostedParser",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _replace(self, text: str, old: str, new: str) -> str:
        call = IntrinsicCall(
            symbol="__string_replace",
            args=(text, old, new),
            source="HostedParser",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _error_here(self, message: str):
        token = self._peek()
        return self._make_error(message, token.line, token.column)

    def _make_error(self, message: str, line: int, column: int):
        return ParseError(f"{message} at {line}:{column}")

    def _peek(self) -> Token:
        return super()._peek()

    def _advance(self) -> Token:
        return super()._advance()


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
    plan = ExecutionPlan(name="lex_dump", path=path)
    source = _host_read_to_string(path, plan)
    lexer = HostedLexer(source)
    tokens = lexer.tokenize()
    text = dump_tokens(tokens)
    output = _host_println(text, plan, source="lex_dump")
    plan.steps.append(PlanStep("tokenize", f"{len(tokens)} tokens"))
    plan.steps.append(PlanStep("dump_tokens", "render token stream"))
    plan.intrinsic_calls.extend(lexer.trace)
    return ExecutionResult(output=output, plan=plan)


def run_ast_dump(path: Path) -> ExecutionResult:
    plan = ExecutionPlan(name="ast_dump", path=path)
    source = _host_read_to_string(path, plan)
    lexer = HostedLexer(source)
    tokens = lexer.tokenize()
    parser = HostedParser(tokens)
    ast = parser.parse_source_file()
    output = _host_println(dump_source_file(ast), plan, source="ast_dump")
    plan.steps.append(PlanStep("tokenize", f"{len(tokens)} tokens"))
    plan.steps.append(PlanStep("parse_source_file", "build SourceFile AST"))
    plan.steps.append(PlanStep("parse_pattern_helpers", "dispatch hosted parser string helpers"))
    plan.steps.append(PlanStep("dump_source_file", "render AST dump"))
    plan.intrinsic_calls.extend(lexer.trace)
    plan.intrinsic_calls.extend(parser.trace)
    return ExecutionResult(output=output, plan=plan)


def _host_read_to_string(path: Path, plan: ExecutionPlan) -> str:
    call = IntrinsicCall(
        symbol="__host_read_to_string",
        args=(str(path),),
        source="HostedCommand",
    )
    plan.intrinsic_calls.append(call)
    plan.steps.append(PlanStep("read_source", str(path)))
    return dispatch(call).value


def _host_println(text: str, plan: ExecutionPlan, source: str) -> str:
    call = IntrinsicCall(
        symbol="__host_println",
        args=(text,),
        source=source,
    )
    plan.intrinsic_calls.append(call)
    plan.steps.append(PlanStep("println", source))
    dispatch(call)
    return text
