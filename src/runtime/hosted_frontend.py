from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from runtime.compat import *
from compiler.ast import namepattern, variantpattern, wildcardpattern, dump_source_file
from compiler.lexer.tokens import keywords, token, tokenkind, dump_tokens
from compiler.parser.parser import parseerror, parser
from runtime.intrinsic_dispatch import intrinsiccall, dispatch


@dataclass
class hostedlexerror(exception):
    message: str
    line: int
    column: int

    def __str__(self) -> str:
        return f"{self.message} at {self.line}:{self.column}"


@dataclass
class hostedlexer:
    source: str
    trace: list[intrinsiccall] = field(default_factory=list)
    index: int = 0
    line: int = 1
    column: int = 1

    def tokenize(self) -> list[token]:
        tokens: list[token] = []
        while not self.is_eof():
            self.skip_ignored()
            if self.is_eof():
                break
            start_line = self.line
            start_col = self.column
            ch = self.peek()
            if ch.isalpha() or ch == "_":
                value = self.read_identifier()
                kind = tokenkind.keyword if value in keywords else tokenkind.ident
                tokens.append(token(kind, value, start_line, start_col))
                continue
            if ch.isdigit():
                tokens.append(token(tokenkind.int, self.read_number(), start_line, start_col))
                continue
            if ch == '"':
                tokens.append(token(tokenkind.string, self.read_string(), start_line, start_col))
                continue
            tokens.append(token(tokenkind.symbol, self.read_symbol(), start_line, start_col))
        tokens.append(token(tokenkind.eof, "<eof>", self.line, self.column))
        return tokens

    def skip_ignored(self) -> none:
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
                        raise hostedlexerror("unterminated block comment", self.line, self.column)
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
                    raise hostedlexerror("unterminated escape sequence", self.line, self.column)
                out.append(self.advance())
                continue
            if ch == '"':
                return "".join(out)
        raise hostedlexerror("unterminated string literal", self.line, self.column)

    def read_symbol(self) -> str:
        for symbol in ("->", ":", "==", "!=", "<=", ">=", "&&", "||", "..=", ".."):
            if self.match_text(symbol):
                out = []
                for _ in symbol:
                    out.append(self.advance())
                return "".join(out)
        ch = self.peek()
        if ch in "()[]{}.,:;+-*/%!=<>?&|":
            return self.advance()
        raise hostedlexerror(f"unexpected character {ch!r}", self.line, self.column)

    def match_text(self, text: str) -> bool:
        return self._slice(self.index, self.index + self._len(text)) == text

    def peek(self) -> str:
        if self.is_eof():
            raise hostedlexerror("unexpected eof", self.line, self.column)
        return self._char_at(self.index)

    def advance(self) -> str:
        if self.is_eof():
            raise hostedlexerror("unexpected eof", self.line, self.column)
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
        call = intrinsiccall(symbol="__runtime_len", args=(value,), source="hostedlexer")
        self.trace.append(call)
        return dispatch(call).value

    def _char_at(self, index: int) -> str:
        call = intrinsiccall(
            symbol="__string_char_at",
            args=(self.source, index),
            source="hostedlexer",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _slice(self, start: int, end: int) -> str:
        call = intrinsiccall(
            symbol="__string_slice",
            args=(self.source, start, end),
            source="hostedlexer",
        )
        self.trace.append(call)
        return dispatch(call).value


@dataclass
class hostedparser(parser):
    trace: list[intrinsiccall] = field(default_factory=list)

    def _parse_pattern(self):
        if self._eat_ident_value("_"):
            return wildcardpattern()
        path = self._parse_path()
        if self._eat_symbol("("):
            args = []
            if not self._at_symbol(")"):
                while true:
                    args.append(self._parse_pattern())
                    if not self._eat_symbol(","):
                        break
                    if self._at_symbol(")"):
                        break
            self._expect_symbol(")")
            return variantpattern(path=path, args=args)
        if self._path_contains_dot(path) or self._starts_with_upper(path):
            return variantpattern(path=path)
        return namepattern(name=path)

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
        if token.kind == tokenkind.keyword and token.value == value:
            return self._advance()
        raise self._make_error(self._concat("expected keyword ", value), token.line, token.column)

    def _expect_symbol(self, value: str):
        token = self._peek()
        if token.kind == tokenkind.symbol and token.value == value:
            return self._advance()
        raise self._make_error(self._concat("expected symbol ", value), token.line, token.column)

    def _expect_ident(self) -> str:
        token = self._peek()
        if token.kind == tokenkind.ident:
            self._advance()
            return token.value
        if token.kind == tokenkind.keyword and token.value == "self":
            self._advance()
            return token.value
        raise self._make_error("expected identifier", token.line, token.column)

    def _path_contains_dot(self, path: str) -> bool:
        i = 0
        while i < self._len(path):
            if self._char_at(path, i) == ".":
                return true
            i += 1
        return false

    def _starts_with_upper(self, text: str) -> bool:
        if text == "":
            return false
        ch = self._char_at(text, 0)
        return "a" <= ch <= "z"

    def _parse_type_text(self, stop_values: set[str]) -> str:
        parts: list[str] = []
        bracket = 0
        paren = 0

        while true:
            token = self._peek()
            if token.kind == tokenkind.eof:
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
        first = true
        for value in values:
            if not first:
                out = self._concat(out, sep)
            out = self._concat(out, value)
            first = false
        return out

    def _len(self, value: object) -> int:
        call = intrinsiccall(symbol="__runtime_len", args=(value,), source="hostedparser")
        self.trace.append(call)
        return dispatch(call).value

    def _char_at(self, text: str, index: int) -> str:
        call = intrinsiccall(
            symbol="__string_char_at",
            args=(text, index),
            source="hostedparser",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _concat(self, left: str, right: str) -> str:
        call = intrinsiccall(
            symbol="__string_concat",
            args=(left, right),
            source="hostedparser",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _replace(self, text: str, old: str, new: str) -> str:
        call = intrinsiccall(
            symbol="__string_replace",
            args=(text, old, new),
            source="hostedparser",
        )
        self.trace.append(call)
        return dispatch(call).value

    def _error_here(self, message: str):
        token = self._peek()
        return self._make_error(message, token.line, token.column)

    def _make_error(self, message: str, line: int, column: int):
        return parseerror(f"{message} at {line}:{column}")

    def _peek(self, offset: int = 0) -> token:
        return super()._peek(offset)

    def _advance(self) -> token:
        return super()._advance()


@dataclass(frozen=true)
class planstep:
    kind: str
    detail: str


@dataclass
class executionplan:
    name: str
    path: path
    steps: list[planstep] = field(default_factory=list)
    intrinsic_calls: list[intrinsiccall] = field(default_factory=list)


@dataclass
class executionresult:
    output: str
    plan: executionplan


def run_lex_dump(path: path) -> executionresult:
    plan = executionplan(name="lex_dump", path=path)
    source = _host_read_to_string(path, plan)
    lexer = hostedlexer(source)
    tokens = lexer.tokenize()
    text = dump_tokens(tokens)
    output = _host_println(text, plan, source="lex_dump")
    plan.steps.append(planstep("tokenize", f"{len(tokens)} tokens"))
    plan.steps.append(planstep("dump_tokens", "render token stream"))
    plan.intrinsic_calls.extend(lexer.trace)
    return executionresult(output=output, plan=plan)


def run_ast_dump(path: path) -> executionresult:
    plan = executionplan(name="ast_dump", path=path)
    source = _host_read_to_string(path, plan)
    lexer = hostedlexer(source)
    tokens = lexer.tokenize()
    parser = hostedparser(tokens)
    ast = parser.parse_source_file()
    output = _host_println(dump_source_file(ast), plan, source="ast_dump")
    plan.steps.append(planstep("tokenize", f"{len(tokens)} tokens"))
    plan.steps.append(planstep("parse_source_file", "build sourcefile ast"))
    plan.steps.append(planstep("parse_pattern_helpers", "dispatch hosted parser string helpers"))
    plan.steps.append(planstep("dump_source_file", "render ast dump"))
    plan.intrinsic_calls.extend(lexer.trace)
    plan.intrinsic_calls.extend(parser.trace)
    return executionresult(output=output, plan=plan)


def _host_read_to_string(path: path, plan: executionplan) -> str:
    call = intrinsiccall(
        symbol="__host_read_to_string",
        args=(str(path),),
        source="hostedcommand",
    )
    plan.intrinsic_calls.append(call)
    plan.steps.append(planstep("read_source", str(path)))
    return dispatch(call).value


def _host_println(text: str, plan: executionplan, source: str) -> str:
    call = intrinsiccall(
        symbol="__host_println",
        args=(text,),
        source=source,
    )
    plan.intrinsic_calls.append(call)
    plan.steps.append(planstep("println", source))
    dispatch(call)
    return text
