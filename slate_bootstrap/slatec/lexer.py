from __future__ import annotations

from dataclasses import dataclass


class LexError(Exception):
    pass


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    line: int
    column: int


KEYWORDS = {"package", "func", "let", "var", "for", "in"}
SYMBOLS = {"(", ")", "{", "}", ",", "+", "=", ";", "<"}


class Lexer:
    def __init__(self, source: str) -> None:
        self.source = source
        self.index = 0
        self.line = 1
        self.column = 1

    def tokenize(self) -> list[Token]:
        tokens: list[Token] = []
        while not self._eof():
            ch = self._peek()
            if ch in " \t\r":
                self._advance()
                continue
            if ch == "\n":
                self._advance()
                self.line += 1
                self.column = 1
                continue
            if ch == "/" and self._peek_next() == "/":
                self._skip_comment()
                continue
            if ch.isalpha() or ch == "_":
                tokens.append(self._read_ident())
                continue
            if ch.isdigit():
                tokens.append(self._read_int())
                continue
            if ch == '"':
                tokens.append(self._read_string())
                continue
            if ch == "<" and self._peek_next() == "=":
                tokens.append(Token("symbol", "<=", self.line, self.column))
                self._advance()
                self._advance()
                continue
            if ch == "." and self._peek_next() == ".":
                tokens.append(Token("symbol", "..", self.line, self.column))
                self._advance()
                self._advance()
                continue
            if ch in SYMBOLS:
                tokens.append(Token("symbol", ch, self.line, self.column))
                self._advance()
                continue
            raise LexError(f"unexpected character {ch!r} at {self.line}:{self.column}")
        tokens.append(Token("eof", "", self.line, self.column))
        return tokens

    def _read_ident(self) -> Token:
        line = self.line
        column = self.column
        chars: list[str] = []
        while not self._eof():
            ch = self._peek()
            if not (ch.isalnum() or ch == "_"):
                break
            chars.append(ch)
            self._advance()
        value = "".join(chars)
        kind = "keyword" if value in KEYWORDS else "ident"
        return Token(kind, value, line, column)

    def _read_int(self) -> Token:
        line = self.line
        column = self.column
        chars: list[str] = []
        while not self._eof():
            ch = self._peek()
            if not ch.isdigit():
                break
            chars.append(ch)
            self._advance()
        return Token("int", "".join(chars), line, column)

    def _read_string(self) -> Token:
        line = self.line
        column = self.column
        self._advance()
        chars: list[str] = []
        while not self._eof():
            ch = self._peek()
            if ch == '"':
                self._advance()
                return Token("string", "".join(chars), line, column)
            if ch == "\\":
                self._advance()
                if self._eof():
                    break
                escaped = self._peek()
                escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
                chars.append(escapes.get(escaped, escaped))
                self._advance()
                continue
            chars.append(ch)
            self._advance()
        raise LexError(f"unterminated string at {line}:{column}")

    def _skip_comment(self) -> None:
        while not self._eof() and self._peek() != "\n":
            self._advance()

    def _peek(self) -> str:
        return self.source[self.index]

    def _peek_next(self) -> str:
        if self.index + 1 >= len(self.source):
            return "\0"
        return self.source[self.index + 1]

    def _advance(self) -> None:
        self.index += 1
        self.column += 1

    def _eof(self) -> bool:
        return self.index >= len(self.source)
