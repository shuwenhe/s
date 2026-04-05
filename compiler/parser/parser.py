from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

from compiler.ast import (
    AssignStmt,
    BlockExpr,
    BinaryExpr,
    BoolExpr,
    BorrowExpr,
    CallExpr,
    CForStmt,
    EnumDecl,
    EnumVariant,
    Expr,
    ExprStmt,
    Field,
    FunctionDecl,
    FunctionSig,
    ForExpr,
    IfExpr,
    ImplDecl,
    IncrementStmt,
    IndexExpr,
    IntExpr,
    LetStmt,
    MatchArm,
    MatchExpr,
    MemberExpr,
    NameExpr,
    NamePattern,
    Param,
    Pattern,
    ReturnStmt,
    SourceFile,
    StringExpr,
    StructDecl,
    TraitDecl,
    UseDecl,
    VariantPattern,
    WhileExpr,
    WildcardPattern,
)
from compiler.lexer import Lexer, Token, TokenKind


class ParseError(Exception):
    pass


def parse_source(source: str) -> SourceFile:
    tokens = Lexer(source).tokenize()
    return Parser(tokens).parse_source_file()


@dataclass
class Parser:
    tokens: List[Token]

    def __post_init__(self) -> None:
        self.index = 0

    def parse_source_file(self) -> SourceFile:
        self._expect_keyword("package")
        package = self._parse_path()
        uses: List[UseDecl] = []
        items: List[object] = []
        while self._at_keyword("use"):
            uses.append(self._parse_use_decl())
        while not self._at(TokenKind.EOF):
            items.append(self._parse_item())
        return SourceFile(package=package, uses=uses, items=items)

    def _parse_use_decl(self) -> UseDecl:
        self._expect_keyword("use")
        path = self._parse_use_path()
        alias = None
        if self._at_keyword("as"):
            self._advance()
            alias = self._expect_ident()
        return UseDecl(path=path, alias=alias)

    def _parse_item(self) -> object:
        is_public = self._eat_keyword("pub")
        if self._at_keyword("func"):
            return self._parse_function_decl(is_public)
        if self._at_keyword("struct"):
            return self._parse_struct_decl(is_public)
        if self._at_keyword("enum"):
            return self._parse_enum_decl(is_public)
        if self._at_keyword("trait"):
            return self._parse_trait_decl(is_public)
        if self._at_keyword("impl"):
            return self._parse_impl_decl()
        token = self._peek()
        raise ParseError(f"unexpected token {token.value!r} at {token.line}:{token.column}")

    def _parse_function_decl(self, is_public: bool) -> FunctionDecl:
        sig, body = self._parse_function(require_body=True)
        return FunctionDecl(sig=sig, body=body, is_public=is_public)

    def _parse_struct_decl(self, is_public: bool) -> StructDecl:
        self._expect_keyword("struct")
        name = self._expect_ident()
        generics = self._parse_generic_params()
        self._expect_symbol("{")
        fields: List[Field] = []
        while not self._eat_symbol("}"):
            field_public = self._eat_keyword("pub")
            field_name = self._expect_ident()
            self._expect_symbol(":")
            field_type = self._parse_type_text(stop_values={",", "}"})
            fields.append(Field(name=field_name, type_name=field_type, is_public=field_public))
            self._eat_symbol(",")
        return StructDecl(name=name, generics=generics, fields=fields, is_public=is_public)

    def _parse_enum_decl(self, is_public: bool) -> EnumDecl:
        self._expect_keyword("enum")
        name = self._expect_ident()
        generics = self._parse_generic_params()
        self._expect_symbol("{")
        variants: List[EnumVariant] = []
        while not self._eat_symbol("}"):
            variant_name = self._expect_ident()
            payload = None
            if self._eat_symbol("("):
                payload = self._parse_type_text(stop_values={")"})
                self._expect_symbol(")")
            variants.append(EnumVariant(name=variant_name, payload=payload))
            self._eat_symbol(",")
        return EnumDecl(name=name, generics=generics, variants=variants, is_public=is_public)

    def _parse_trait_decl(self, is_public: bool) -> TraitDecl:
        self._expect_keyword("trait")
        name = self._expect_ident()
        generics = self._parse_generic_params()
        self._expect_symbol("{")
        methods: List[FunctionSig] = []
        while not self._eat_symbol("}"):
            sig, _ = self._parse_function(require_body=False)
            methods.append(sig)
            self._expect_symbol(";")
        return TraitDecl(name=name, generics=generics, methods=methods, is_public=is_public)

    def _parse_impl_decl(self) -> ImplDecl:
        self._expect_keyword("impl")
        generics = self._parse_generic_params()
        first = self._parse_path()
        trait_name: Optional[str] = None
        target = first
        if self._eat_keyword("for"):
            trait_name = first
            target = self._parse_path()
        self._parse_where_clause()
        self._expect_symbol("{")
        methods: List[FunctionDecl] = []
        while not self._eat_symbol("}"):
            is_public = self._eat_keyword("pub")
            methods.append(self._parse_function_decl(is_public))
        return ImplDecl(target=target, trait_name=trait_name, generics=generics, methods=methods)

    def _parse_function(self, require_body: bool) -> tuple[FunctionSig, Optional[BlockExpr]]:
        self._expect_keyword("func")
        name = self._expect_ident()
        generics = self._parse_generic_params()
        self._expect_symbol("(")
        params = self._parse_params()
        self._expect_symbol(")")
        return_type = None
        if self._eat_symbol("->"):
            return_type = self._parse_type_text(stop_values={"where", "{", ";"})
        self._parse_where_clause()
        body = self._parse_block_expr() if require_body else None
        return FunctionSig(name=name, generics=generics, params=params, return_type=return_type), body

    def _parse_params(self) -> List[Param]:
        params: List[Param] = []
        if self._at_symbol(")"):
            return params
        while True:
            name = self._parse_param_name()
            self._expect_symbol(":")
            type_name = self._parse_type_text(stop_values={",", ")"})
            params.append(Param(name=name, type_name=type_name))
            if not self._eat_symbol(","):
                break
            if self._at_symbol(")"):
                break
        return params

    def _parse_param_name(self) -> str:
        if self._eat_keyword("mut"):
            return "mut " + self._expect_ident()
        if self._eat_symbol("&"):
            prefix = "&mut " if self._eat_keyword("mut") else "&"
            if self._eat_keyword("self"):
                return prefix + "self"
            return prefix + self._expect_ident()
        if self._eat_keyword("self"):
            return "self"
        return self._expect_ident()

    def _parse_generic_params(self) -> List[str]:
        generics: List[str] = []
        if not self._eat_symbol("["):
            return generics
        while not self._eat_symbol("]"):
            name = self._expect_ident()
            if self._eat_symbol(":"):
                bounds = [self._parse_path()]
                while self._eat_symbol("+"):
                    bounds.append(self._parse_path())
                name = f"{name}: {' + '.join(bounds)}"
            generics.append(name)
            self._eat_symbol(",")
        return generics

    def _parse_where_clause(self) -> None:
        if not self._eat_keyword("where"):
            return
        while True:
            self._parse_type_text(stop_values={",", "{", ";"})
            if not self._eat_symbol(","):
                break
            if self._at_symbol("{") or self._at_symbol(";"):
                break

    def _parse_block_expr(self) -> BlockExpr:
        self._expect_symbol("{")
        statements = []
        final_expr = None
        while not self._at_symbol("}"):
            if self._starts_stmt():
                statements.append(self._parse_stmt())
                continue
            expr = self._parse_expr()
            if self._eat_symbol(";"):
                statements.append(ExprStmt(expr))
                continue
            final_expr = expr
            break
        self._expect_symbol("}")
        return BlockExpr(statements=statements, final_expr=final_expr)

    def _starts_stmt(self) -> bool:
        return (
            self._at_keyword("let")
            or self._at_keyword("return")
            or self._at_keyword("for")
            or self._looks_like_typed_let()
            or self._looks_like_assignment()
            or self._looks_like_increment()
        )

    def _parse_stmt(self):
        if self._at_keyword("let"):
            return self._parse_let_stmt()
        if self._at_keyword("return"):
            return self._parse_return_stmt()
        if self._at_keyword("for"):
            return self._parse_c_for_stmt()
        if self._looks_like_typed_let():
            return self._parse_typed_let_stmt()
        if self._looks_like_assignment():
            return self._parse_assign_stmt()
        if self._looks_like_increment():
            return self._parse_increment_stmt()
        token = self._peek()
        raise ParseError(f"unexpected statement {token.value!r} at {token.line}:{token.column}")

    def _parse_let_stmt(self) -> LetStmt:
        self._expect_keyword("let")
        name = self._expect_ident()
        type_name = None
        if self._eat_symbol(":"):
            type_name = self._parse_type_text(stop_values={"="})
        self._expect_symbol("=")
        value = self._parse_expr()
        self._eat_symbol(";")
        return LetStmt(name=name, type_name=type_name, value=value)

    def _parse_typed_let_stmt(self) -> LetStmt:
        type_name = self._advance().value
        name = self._expect_ident()
        self._expect_symbol("=")
        value = self._parse_expr()
        self._eat_symbol(";")
        return LetStmt(name=name, type_name=type_name, value=value)

    def _parse_assign_stmt(self) -> AssignStmt:
        name = self._expect_ident()
        self._expect_symbol("=")
        value = self._parse_expr()
        self._eat_symbol(";")
        return AssignStmt(name=name, value=value)

    def _parse_increment_stmt(self) -> IncrementStmt:
        name = self._expect_ident()
        self._expect_symbol("++")
        self._eat_symbol(";")
        return IncrementStmt(name=name)

    def _parse_c_for_stmt(self) -> CForStmt:
        self._expect_keyword("for")
        self._expect_symbol("(")
        init = self._parse_for_clause_stmt()
        self._expect_symbol(";")
        condition = self._parse_expr()
        self._expect_symbol(";")
        step = self._parse_for_clause_stmt()
        self._expect_symbol(")")
        body = self._parse_block_expr()
        return CForStmt(init=init, condition=condition, step=step, body=body)

    def _parse_for_clause_stmt(self):
        if self._at_keyword("let"):
            return self._parse_let_stmt()
        if self._looks_like_typed_let():
            return self._parse_typed_let_stmt()
        if self._looks_like_assignment():
            return self._parse_assign_stmt()
        if self._looks_like_increment():
            return self._parse_increment_stmt()
        token = self._peek()
        raise ParseError(f"unexpected for clause {token.value!r} at {token.line}:{token.column}")

    def _parse_return_stmt(self) -> ReturnStmt:
        self._expect_keyword("return")
        if self._eat_symbol(";"):
            return ReturnStmt(value=None)
        value = self._parse_expr()
        self._eat_symbol(";")
        return ReturnStmt(value=value)

    def _parse_expr(self) -> Expr:
        if self._at_keyword("match"):
            return self._parse_match_expr()
        if self._at_keyword("if"):
            return self._parse_if_expr()
        if self._at_keyword("while"):
            return self._parse_while_expr()
        if self._at_keyword("for"):
            return self._parse_for_expr()
        return self._parse_binary_expr(0)

    def _parse_match_expr(self) -> MatchExpr:
        self._expect_keyword("match")
        subject = self._parse_expr()
        self._expect_symbol("{")
        arms: List[MatchArm] = []
        while not self._eat_symbol("}"):
            pattern = self._parse_pattern()
            self._expect_symbol("=>")
            expr = self._parse_expr()
            arms.append(MatchArm(pattern=pattern, expr=expr))
            self._eat_symbol(",")
        return MatchExpr(subject=subject, arms=arms)

    def _parse_if_expr(self) -> IfExpr:
        self._expect_keyword("if")
        condition = self._parse_expr()
        then_branch = self._parse_block_expr()
        else_branch: Optional[Expr] = None
        if self._eat_keyword("else"):
            if self._at_keyword("if"):
                else_branch = self._parse_if_expr()
            else:
                else_branch = self._parse_block_expr()
        return IfExpr(condition=condition, then_branch=then_branch, else_branch=else_branch)

    def _parse_while_expr(self) -> WhileExpr:
        self._expect_keyword("while")
        condition = self._parse_expr()
        body = self._parse_block_expr()
        return WhileExpr(condition=condition, body=body)

    def _parse_for_expr(self) -> ForExpr:
        self._expect_keyword("for")
        name = self._expect_ident()
        self._expect_keyword("in")
        iterable = self._parse_expr()
        body = self._parse_block_expr()
        return ForExpr(name=name, iterable=iterable, body=body)

    def _parse_pattern(self) -> Pattern:
        if self._eat_ident_value("_"):
            return WildcardPattern()
        path = self._parse_path()
        if self._eat_symbol("("):
            args: List[Pattern] = []
            if not self._at_symbol(")"):
                while True:
                    args.append(self._parse_pattern())
                    if not self._eat_symbol(","):
                        break
                    if self._at_symbol(")"):
                        break
            self._expect_symbol(")")
            return VariantPattern(path=path, args=args)
        if "." in path or path[:1].isupper():
            return VariantPattern(path=path)
        return NamePattern(name=path)

    def _parse_binary_expr(self, min_precedence: int) -> Expr:
        expr = self._parse_unary_expr()
        while True:
            token = self._peek()
            precedence = self._binary_precedence(token.value)
            if precedence < min_precedence:
                break
            op = self._advance().value
            rhs = self._parse_binary_expr(precedence + 1)
            expr = BinaryExpr(left=expr, op=op, right=rhs)
        return expr

    def _parse_unary_expr(self) -> Expr:
        if self._eat_symbol("&"):
            mutable = self._eat_keyword("mut")
            return BorrowExpr(target=self._parse_unary_expr(), mutable=mutable)
        return self._parse_call_expr()

    def _parse_call_expr(self) -> Expr:
        expr = self._parse_primary_expr()
        while True:
            if self._eat_symbol("("):
                args: List[Expr] = []
                if not self._at_symbol(")"):
                    while True:
                        args.append(self._parse_expr())
                        if not self._eat_symbol(","):
                            break
                        if self._at_symbol(")"):
                            break
                self._expect_symbol(")")
                expr = CallExpr(callee=expr, args=args)
                continue
            if self._eat_symbol("."):
                expr = MemberExpr(target=expr, member=self._expect_ident())
                continue
            if self._eat_symbol("["):
                index = self._parse_expr()
                self._expect_symbol("]")
                expr = IndexExpr(target=expr, index=index)
                continue
            break
        return expr

    def _parse_primary_expr(self) -> Expr:
        token = self._peek()
        if token.kind == TokenKind.INT:
            self._advance()
            return IntExpr(value=token.value)
        if token.kind == TokenKind.STRING:
            self._advance()
            return StringExpr(value=token.value)
        if self._at_keyword("true"):
            self._advance()
            return BoolExpr(value=True)
        if self._at_keyword("false"):
            self._advance()
            return BoolExpr(value=False)
        if self._at_symbol("{"):
            return self._parse_block_expr()
        if self._eat_symbol("("):
            expr = self._parse_expr()
            self._expect_symbol(")")
            return expr
        return NameExpr(name=self._parse_expr_name())

    def _binary_precedence(self, op: str) -> int:
        table = {
            "||": 1,
            "&&": 2,
            "==": 3,
            "!=": 3,
            "<": 4,
            "<=": 4,
            ">": 4,
            ">=": 4,
            "+": 5,
            "-": 5,
            "*": 6,
            "/": 6,
            "%": 6,
        }
        return table.get(op, -1)

    def _parse_use_path(self) -> str:
        parts = [self._expect_ident()]
        while self._eat_symbol("."):
            if self._eat_symbol("{"):
                members = []
                while not self._eat_symbol("}"):
                    member = self._expect_ident()
                    if self._eat_keyword("as"):
                        member += f" as {self._expect_ident()}"
                    members.append(member)
                    self._eat_symbol(",")
                return ".".join(parts) + ".{" + ", ".join(members) + "}"
            parts.append(self._expect_ident())
        return ".".join(parts)

    def _parse_path(self) -> str:
        parts = [self._expect_ident()]
        while self._eat_symbol("."):
            parts.append(self._expect_ident())
        if self._at_symbol("["):
            parts[-1] += self._parse_bracket_group()
        return ".".join(parts)

    def _parse_expr_name(self) -> str:
        return self._expect_ident()

    def _parse_type_text(self, stop_values: set[str]) -> str:
        parts: List[str] = []
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
        text = " ".join(parts)
        text = text.replace(" . ", ".")
        text = text.replace("[ ", "[").replace(" ]", "]")
        text = text.replace("( ", "(").replace(" )", ")")
        text = text.replace(" ,", ",")
        text = text.replace("& mut ", "&mut ")
        text = text.replace("[] ", "[]")
        text = text.replace(" [", "[")
        return text.strip()

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
        text = " ".join(parts).replace("[ ", "[").replace(" ]", "]").replace(" ,", ",")
        return text

    def _at(self, kind: TokenKind) -> bool:
        return self._peek().kind == kind

    def _looks_like_typed_let(self) -> bool:
        return (
            self._peek().kind in {TokenKind.IDENT, TokenKind.KEYWORD}
            and self._peek(1).kind == TokenKind.IDENT
            and self._peek(2).kind == TokenKind.SYMBOL
            and self._peek(2).value == "="
        )

    def _looks_like_assignment(self) -> bool:
        return (
            self._peek().kind == TokenKind.IDENT
            and self._peek(1).kind == TokenKind.SYMBOL
            and self._peek(1).value == "="
        )

    def _looks_like_increment(self) -> bool:
        return (
            self._peek().kind == TokenKind.IDENT
            and self._peek(1).kind == TokenKind.SYMBOL
            and self._peek(1).value == "++"
        )

    def _at_keyword(self, value: str) -> bool:
        token = self._peek()
        return token.kind == TokenKind.KEYWORD and token.value == value

    def _at_symbol(self, value: str) -> bool:
        token = self._peek()
        return token.kind == TokenKind.SYMBOL and token.value == value

    def _eat_keyword(self, value: str) -> bool:
        if self._at_keyword(value):
            self._advance()
            return True
        return False

    def _eat_ident_value(self, value: str) -> bool:
        token = self._peek()
        if token.kind == TokenKind.IDENT and token.value == value:
            self._advance()
            return True
        return False

    def _eat_symbol(self, value: str) -> bool:
        if self._at_symbol(value):
            self._advance()
            return True
        return False

    def _expect_keyword(self, value: str) -> Token:
        token = self._peek()
        if token.kind == TokenKind.KEYWORD and token.value == value:
            return self._advance()
        raise ParseError(f"expected keyword {value!r} at {token.line}:{token.column}")

    def _expect_symbol(self, value: str) -> Token:
        token = self._peek()
        if token.kind == TokenKind.SYMBOL and token.value == value:
            return self._advance()
        raise ParseError(f"expected symbol {value!r} at {token.line}:{token.column}")

    def _expect_ident(self) -> str:
        token = self._peek()
        if token.kind == TokenKind.KEYWORD and token.value == "self":
            self._advance()
            return token.value
        if token.kind == TokenKind.IDENT:
            self._advance()
            return token.value
        raise ParseError(f"expected identifier at {token.line}:{token.column}")

    def _peek(self, offset: int = 0) -> Token:
        index = min(self.index + offset, len(self.tokens) - 1)
        return self.tokens[index]

    def _advance(self) -> Token:
        token = self.tokens[self.index]
        self.index += 1
        return token
