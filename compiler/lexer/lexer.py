from __future__ import annotations

from dataclasses import dataclass

from .tokens import KEYWORDS, Token, TokenKind


class LexError(Exception):
    pass


@dataclass
class Lexer:
    source: str

    def __post_init__(self) -> None:
        self.index = 0
        self.line = 1
        self.column = 1

    def tokenize(self) -> list[Token]:
        tokens: list[Token] = []
        while not self._is_eof():
            self._skip_ignored()
            if self._is_eof():
                break
            start_line = self.line
            start_col = self.column
            ch = self._peek()
            if ch.isalpha() or ch == "_":
                value = self._read_identifier()
                kind = TokenKind.KEYWORD if value in KEYWORDS else TokenKind.IDENT
                tokens.append(Token(kind, value, start_line, start_col))
                continue
            if ch.isdigit():
                tokens.append(Token(TokenKind.INT, self._read_number(), start_line, start_col))
                continue
            if ch == '"':
                tokens.append(Token(TokenKind.STRING, self._read_string(), start_line, start_col))
                continue
            symbol = self._read_symbol()
            tokens.append(Token(TokenKind.SYMBOL, symbol, start_line, start_col))
        tokens.append(Token(TokenKind.EOF, "<eof>", self.line, self.column))
        return tokens

    def _skip_ignored(self) -> None:
        while not self._is_eof():
            ch = self._peek()
            if ch in " \t\r\n":
                self._advance()
                continue
            if self._match("//"):
                while not self._is_eof() and self._peek() != "\n":
                    self._advance()
                continue
            if self._match("/*"):
                self._advance()
                self._advance()
                depth = 1
                while depth > 0:
                    if self._is_eof():
                        raise LexError("unterminated block comment")
                    if self._match("/*"):
                        depth += 1
                        self._advance()
                        self._advance()
                        continue
                    if self._match("*/"):
                        depth -= 1
                        self._advance()
                        self._advance()
                        continue
                    self._advance()
                continue
            break

    def _read_identifier(self) -> str:
        chars = []
        while not self._is_eof() and (self._peek().isalnum() or self._peek() == "_"):
            chars.append(self._advance())
        return "".join(chars)

    def _read_number(self) -> str:
        chars = []
        while not self._is_eof() and self._peek().isdigit():
            chars.append(self._advance())
        return "".join(chars)

    def _read_string(self) -> str:
        quote = self._advance()
        chars = [quote]
        while not self._is_eof():
            ch = self._advance()
            chars.append(ch)
            if ch == "\\":
                if self._is_eof():
                    raise LexError("unterminated escape sequence")
                chars.append(self._advance())
                continue
            if ch == '"':
                return "".join(chars)
        raise LexError("unterminated string literal")

    def _read_symbol(self) -> str:
        for symbol in ("->", "=>", "==", "!=", "<=", ">=", "&&", "||", "++", "..=", ".."):
            if self._match(symbol):
                for _ in symbol:
                    self._advance()
                return symbol
        ch = self._peek()
        if ch in "()[]{}.,:;+-*/%!=<>?&|":
            return self._advance()
        raise LexError(f"unexpected character {ch!r} at {self.line}:{self.column}")

    def _match(self, text: str) -> bool:
        return self.source[self.index : self.index + len(text)] == text

    def _peek(self) -> str:
        return self.source[self.index]

    def _advance(self) -> str:
        ch = self.source[self.index]
        self.index += 1
        if ch == "\n":
            self.line += 1
            self.column = 1
        else:
            self.column += 1
        return ch

    def _is_eof(self) -> bool:
        return self.index >= len(self.source)
