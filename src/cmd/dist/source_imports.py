#!/usr/bin/env python3
"""Read S import clauses without treating other declaration strings as imports."""
import ast
import re
import sys
from pathlib import Path


def source_tokens(source):
    pattern = re.compile(r'\s+|"(?:\\.|[^"\\])*"|//[^\n]*|/\*|[\w]+|[^\s]')
    comments = re.compile(r'/\*|\*/')
    position = 0
    while position < len(source):
        match = pattern.match(source, position)
        token = match.group()
        position = match.end()
        if token == '/*':
            depth = 1
            while depth:
                delimiter = comments.search(source, position)
                if delimiter is None:
                    raise ValueError('unterminated block comment')
                depth += 1 if delimiter.group() == '/*' else -1
                position = delimiter.end()
        elif not token.isspace() and not token.startswith('//'):
            yield token


def import_item(tokens, cursor):
    path = tokens[cursor]
    cursor += 1
    if not path.startswith('"'):
        if cursor < len(tokens) and tokens[cursor].startswith('"'):
            path = tokens[cursor]  # alias "package.path"
            cursor += 1
        else:
            while cursor < len(tokens) and tokens[cursor] == '.':
                path += '.' + tokens[cursor + 1]
                cursor += 2
    if path.startswith('"'):
        path = ast.literal_eval(path)
    if cursor < len(tokens) and tokens[cursor] == 'as':
        cursor += 2
    return path, cursor


def imports(source):
    tokens = list(source_tokens(source))
    cursor = 0
    while cursor < len(tokens):
        keyword = tokens[cursor]
        cursor += 1
        if keyword not in ('import', 'use') or cursor >= len(tokens):
            continue
        group = tokens[cursor] == '('
        if group:
            cursor += 1
        while cursor < len(tokens):
            if group and tokens[cursor] == ')':
                cursor += 1
                break
            if group and tokens[cursor] == ';':
                cursor += 1
                continue
            path, cursor = import_item(tokens, cursor)
            yield path
            if not group:
                break


if __name__ == '__main__':
    for module in imports(Path(sys.argv[1]).read_text()):
        print(module)
