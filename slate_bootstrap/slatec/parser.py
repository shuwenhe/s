from __future__ import annotations

from dataclasses import dataclass

from slatec.ast import (
    AssignStmt,
    BinaryExpr,
    ForStmt,
    FunctionDecl,
    IntLiteral,
    LetStmt,
    NameExpr,
    PrintlnStmt,
    SourceFile,
    StringExpr,
)
from slatec.lexer import Token


class ParseError(Exception):
    pass


@dataclass
class Parser:
    tokens: list[Token]

    def __post_init__(self) -> None:
        self.index = 0

    def parse(self) -> SourceFile:
        self._expect_keyword("package")
        package = self._expect("ident").value
        functions: list[FunctionDecl] = []
        while not self._at("eof"):
            functions.append(self._parse_function())
        return SourceFile(package=package, functions=functions)

    def _parse_function(self) -> FunctionDecl:
        self._expect_keyword("func")
        name = self._expect("ident").value
        self._expect_symbol("(")
        self._expect_symbol(")")
        self._expect_symbol("{")
        body = []
        while not self._eat_symbol("}"):
            body.append(self._parse_stmt())
        return FunctionDecl(name=name, body=body)

    def _parse_stmt(self):
        if self._eat_keyword("let") or self._eat_keyword("var"):
            name = self._expect("ident").value
            self._expect_symbol("=")
            return LetStmt(name=name, type_name=None, value=self._parse_expr())
        if self._eat_keyword("for"):
            self._expect_symbol("(")
            init = self._parse_for_init()
            self._expect_symbol(";")
            condition = self._parse_expr()
            self._expect_symbol(";")
            step = self._parse_for_step()
            self._expect_symbol(")")
            self._expect_symbol("{")
            body = []
            while not self._eat_symbol("}"):
                body.append(self._parse_stmt())
            return ForStmt(init=init, condition=condition, step=step, body=body)

        if (
            self._at("ident")
            and self.tokens[self.index + 1].kind == "ident"
            and self.tokens[self.index + 2].kind == "symbol"
            and self.tokens[self.index + 2].value == "="
        ):
            type_name = self._expect("ident").value
            name = self._expect("ident").value
            self._expect_symbol("=")
            return LetStmt(name=name, type_name=type_name, value=self._parse_expr())

        if self._at("ident") and self.tokens[self.index + 1].kind == "symbol" and self.tokens[self.index + 1].value == "=":
            name = self._expect("ident").value
            self._expect_symbol("=")
            return AssignStmt(name=name, value=self._parse_expr())

        callee = self._expect("ident").value
        if callee != "println":
            raise self._error("only println(...) is supported in MVP")
        self._expect_symbol("(")
        value = self._parse_expr()
        self._expect_symbol(")")
        return PrintlnStmt(value)

    def _parse_expr(self):
        expr = self._parse_add_expr()
        while self._eat_symbol("<="):
            expr = BinaryExpr(left=expr, op="<=", right=self._parse_add_expr())
        return expr

    def _parse_add_expr(self):
        expr = self._parse_primary()
        while self._eat_symbol("+"):
            expr = BinaryExpr(left=expr, op="+", right=self._parse_primary())
        return expr

    def _parse_for_init(self):
        if self._eat_keyword("let") or self._eat_keyword("var"):
            name = self._expect("ident").value
            self._expect_symbol("=")
            return LetStmt(name=name, type_name=None, value=self._parse_expr())
        if (
            self._at("ident")
            and self.tokens[self.index + 1].kind == "ident"
            and self.tokens[self.index + 2].kind == "symbol"
            and self.tokens[self.index + 2].value == "="
        ):
            type_name = self._expect("ident").value
            name = self._expect("ident").value
            self._expect_symbol("=")
            return LetStmt(name=name, type_name=type_name, value=self._parse_expr())
        if self._at("ident") and self.tokens[self.index + 1].kind == "symbol" and self.tokens[self.index + 1].value == "=":
            name = self._expect("ident").value
            self._expect_symbol("=")
            return AssignStmt(name=name, value=self._parse_expr())
        raise self._error("expected for-loop initializer")

    def _parse_for_step(self):
        if self._at("ident") and self.tokens[self.index + 1].kind == "symbol" and self.tokens[self.index + 1].value == "=":
            name = self._expect("ident").value
            self._expect_symbol("=")
            return AssignStmt(name=name, value=self._parse_expr())
        raise self._error("expected for-loop step")

    def _parse_primary(self):
        token = self.tokens[self.index]
        if token.kind == "string":
            self.index += 1
            return StringExpr(token.value)
        if token.kind == "int":
            self.index += 1
            return IntLiteral(int(token.value))
        if token.kind == "ident":
            self.index += 1
            return NameExpr(token.value)
        raise self._error("expected expression")

    def _at(self, kind: str) -> bool:
        return self.tokens[self.index].kind == kind

    def _eat_symbol(self, value: str) -> bool:
        token = self.tokens[self.index]
        if token.kind == "symbol" and token.value == value:
            self.index += 1
            return True
        return False

    def _expect_symbol(self, value: str) -> Token:
        token = self.tokens[self.index]
        if token.kind == "symbol" and token.value == value:
            self.index += 1
            return token
        raise self._error(f"expected symbol {value!r}")

    def _expect_keyword(self, value: str) -> Token:
        token = self.tokens[self.index]
        if token.kind == "keyword" and token.value == value:
            self.index += 1
            return token
        raise self._error(f"expected keyword {value!r}")

    def _eat_keyword(self, value: str) -> bool:
        token = self.tokens[self.index]
        if token.kind == "keyword" and token.value == value:
            self.index += 1
            return True
        return False

    def _expect(self, kind: str) -> Token:
        token = self.tokens[self.index]
        if token.kind == kind:
            self.index += 1
            return token
        raise self._error(f"expected {kind}")

    def _error(self, message: str) -> ParseError:
        token = self.tokens[self.index]
        return ParseError(f"{message} at {token.line}:{token.column}")
