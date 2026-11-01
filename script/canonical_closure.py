#!/usr/bin/env python3
"""Audit explicit S package/use dependencies; this does not prove compilability.

--root is the repository, --entry is the source root. Imports require an exact
package declaration. Uses select an exact package or a top-level free function
in the longest existing package prefix. Filenames are never symbol aliases.
Package peers are included conservatively. Runtime, visibility, build selection
and linker inputs remain separate, unproven boundaries.
"""
from __future__ import annotations

import argparse
from collections import defaultdict, deque
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys


LEXEME = re.compile(
    r'(?P<comment>//[^\n]*|/\*.*?\*/)'
    r'|(?P<string>"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|`[^`]*`)'
    r'|(?P<identifier>[A-Za-z_][A-Za-z_0-9]*)'
    r'|(?P<newline>\n)|(?P<space>[ \t\r]+)|(?P<punctuation>.)', re.S,
)


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    line: int
    column: int


def tokenize(text):
    line, column = 1, 1
    for match in LEXEME.finditer(text):
        value, kind = match.group(), match.lastgroup
        if kind not in ("comment", "space"):
            yield Token(kind, value, line, column)
        elif kind == "comment" and "\n" in value:
            # Newlines in comments still delimit top-level declarations.
            yield Token("newline", "\n", line, column)
        newlines = value.count("\n")
        if newlines:
            line, column = line + newlines, len(value.rsplit("\n", 1)[1]) + 1
        else:
            column += len(value)
    yield Token("eof", "", line, column)


def read_path(tokens, index):
    token = tokens[index]
    if token.kind == "string" and token.value.startswith('"'):
        return json.loads(token.value), index + 1
    if token.kind != "identifier":
        raise ValueError("expected a dotted path or quoted import")
    parts = [token.value]
    index += 1
    while tokens[index].value == "." and tokens[index + 1].kind == "identifier":
        parts.append(tokens[index + 1].value)
        index += 2
    return ".".join(parts), index


def scan_source(text):
    tokens = list(tokenize(text))
    package, package_line = None, 0
    dependencies, functions, errors = [], [], []
    index, depth = 0, 0
    while tokens[index].kind != "eof":
        token = tokens[index]
        statement_start = index == 0 or tokens[index - 1].kind == "newline" or tokens[index - 1].value in (";", "}")
        if depth == 0 and statement_start and token.kind == "identifier":
            if token.value == "package":
                try:
                    package, index = read_path(tokens, index + 1)
                    package_line = token.line
                except ValueError as error:
                    errors.append({"line": token.line, "column": token.column,
                                   "reason": "invalid_package_declaration", "detail": str(error)})
                    index += 1
                continue
            if token.value == "func" and tokens[index + 1].kind == "identifier":
                name = tokens[index + 1]
                functions.append({"name": name.value, "line": name.line, "column": name.column})
            if token.value in ("import", "use"):
                kind = token.value
                index += 1
                grouped = kind == "import" and tokens[index].value == "("
                if grouped:
                    index += 1
                try:
                    while True:
                        if grouped:
                            while tokens[index].kind == "newline" or tokens[index].value in (",", ";"):
                                index += 1
                            if tokens[index].value == ")":
                                index += 1
                                break
                        start = tokens[index]
                        alias = None
                        # Go-style import alias followed by a quoted package.
                        if kind == "import" and (start.kind == "identifier" or start.value == ".") and tokens[index + 1].kind == "string":
                            alias, index = start.value, index + 1
                        dependency, index = read_path(tokens, index)
                        if tokens[index].value == "as":
                            index += 1
                            if tokens[index].kind != "identifier":
                                raise ValueError("expected alias")
                            alias, index = tokens[index].value, index + 1
                        if not grouped and tokens[index].kind not in ("newline", "eof") and tokens[index].value != ";":
                            raise ValueError("unsupported dependency selector or trailing syntax")
                        dependencies.append({"dependency": dependency, "syntax": kind,
                                             "alias": alias, "line": start.line,
                                             "column": start.column})
                        if not grouped:
                            break
                except (ValueError, IndexError) as error:
                    errors.append({"line": token.line, "column": token.column,
                                   "reason": "unsupported_dependency_syntax", "detail": str(error)})
                    while tokens[index].kind not in ("newline", "eof"):
                        index += 1
                continue
        if token.kind == "punctuation":
            if token.value in ("{", "(", "["):
                depth += 1
            elif token.value in ("}", ")", "]"):
                depth -= 1
        index += 1
    return {"package": package, "package_line": package_line,
            "dependencies": dependencies, "functions": functions, "errors": errors}


def is_runtime_boundary(dep):
    return dep in ("s", "std", "runtime") or dep.startswith(("std.", "runtime."))


def eligible(path, root):
    parts = path.relative_to(root).parts
    return not (any(part.startswith(".") or part in ("tests", "testdata") for part in parts)
                or path.name.endswith("_test.s") or path.name.startswith("test_"))


def encode_json(value):
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def build(root, entry):
    root, entry = root.resolve(), entry.resolve()
    if not entry.is_file() or not entry.is_relative_to(root / "src"):
        raise ValueError(f"entry must be a file inside {root / 'src'}")
    sources, packages, symbols = {}, defaultdict(list), defaultdict(list)
    for path in sorted((root / "src").rglob("*.s")):
        if not eligible(path, root) and path.resolve() != entry:
            continue
        relative = path.relative_to(root).as_posix()
        info = scan_source(path.read_text(encoding="utf-8"))
        sources[relative] = info
        if info["package"]:
            packages[info["package"]].append(relative)
            for function in info["functions"]:
                symbols[(info["package"], function["name"])].append({
                    "source": relative, "line": function["line"], "column": function["column"]})
    entry_name = entry.relative_to(root).as_posix()
    if not sources[entry_name]["package"]:
        raise ValueError(f"entry has no package declaration: {entry_name}")
    queue, visited = deque([entry_name]), set()
    edges, unresolved, runtime = defaultdict(list), [], set()
    while queue:
        current = queue.popleft()
        if current in visited:
            continue
        visited.add(current)
        info = sources[current]
        unresolved.extend({"source": current, **error} for error in info["errors"])
        for peer in packages[info["package"]]:
            if peer != current:
                edges[current].append({"dependency": peer, "kind": "package-member",
                                       "package": info["package"], "line": info["package_line"]})
                queue.append(peer)
        for dep in info["dependencies"]:
            name = dep["dependency"]
            record = {"source": current, **dep, "package": name, "symbol": None}
            if is_runtime_boundary(name):
                runtime.add(name)
                edges[current].append({**dep, "kind": "runtime-boundary", "status": "NOT_PROVEN"})
                continue
            if name in packages:
                candidates = packages[name]
            elif dep["syntax"] == "import":
                unresolved.append({**record, "reason": "missing_package"})
                continue
            else:
                package = next((prefix for prefix in sorted(packages, key=lambda p: (-len(p), p))
                                if name.startswith(prefix + ".")), None)
                if package is None:
                    unresolved.append({**record, "reason": "missing_package"})
                    continue
                symbol = name[len(package) + 1:]
                record.update(package=package, symbol=symbol)
                definitions = symbols.get((package, symbol), [])
                if len(definitions) != 1:
                    failure = {**record, "reason": "missing_symbol" if not definitions else "ambiguous_symbol"}
                    if definitions:
                        failure["candidates"] = definitions
                    unresolved.append(failure)
                    continue
                definition = definitions[0]
                target = definition["source"]
                edges[current].append({**dep, "dependency": target, "reference": name,
                                       "package": package, "symbol": symbol, "kind": "symbol",
                                       "declaration_line": definition["line"],
                                       "declaration_column": definition["column"],
                                       "accessibility": "NOT_PROVEN"})
                queue.append(target)
                continue
            for target in candidates:
                edges[current].append({**dep, "dependency": target, "reference": name,
                                       "kind": "package", "package": name})
                queue.append(target)
    files = [{"path": path, "package": sources[path]["package"],
              "sha256": hashlib.sha256((root / path).read_bytes()).hexdigest()}
             for path in sorted(visited)]
    payload = {
        "schema_version": 2, "root": entry_name, "files": files,
        "edges": {k: sorted(v, key=lambda edge: (edge["line"], edge["kind"], edge["dependency"]))
                  for k, v in sorted(edges.items())},
        "runtime_dependencies": sorted(runtime), "link_dependencies": [],
        "unresolved_imports": sorted(unresolved, key=lambda item: (item["source"], item["line"], item["column"])),
        "boundaries": {"runtime": "NOT_PROVEN", "link": "NOT_PROVEN",
                       "symbol_accessibility": "NOT_PROVEN", "build_selection": "NOT_PROVEN",
                       "package_cycle_legality": "NOT_PROVEN"},
        "resolution_rules": {"import": "exact declared package", "use": "exact package or unique top-level free function in longest package prefix",
                             "package_files": "all eligible files with equal package declaration",
                             "excluded_sources": "hidden paths, tests/testdata directories, test_*.s, *_test.s",
                             "runtime": "s, std, runtime namespaces recorded as unproven external boundaries"},
    }
    report = {**payload, "manifest_sha256": hashlib.sha256(encode_json(payload).encode()).hexdigest(),
              "manifest_hash_file": "canonical-manifest.json",
              "closure_status": "PASS" if not unresolved else "FAIL",
              "canonical_production_closure": "NOT_PROVEN"}
    return report, 2 if unresolved else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="repository directory")
    parser.add_argument("--entry", type=Path, default=Path("src/cmd/compile/main.s"), help="source entry relative to repository")
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    entry = args.entry if args.entry.is_absolute() else root / args.entry
    try:
        report, status = build(root, entry)
    except (ValueError, OSError) as error:
        parser.exit(2, f"closure: {error}\n")
    out = args.out_dir.resolve()
    if out.is_relative_to(root / "src") or out.is_relative_to(root / "script"):
        parser.exit(2, "closure: output directory must not be inside src/ or script/\n")
    out.mkdir(parents=True, exist_ok=True)
    payload = {key: value for key, value in report.items()
               if key not in ("manifest_sha256", "manifest_hash_file", "closure_status", "canonical_production_closure")}
    outputs = {"canonical-closure.json": report, "canonical-manifest.json": payload,
               "canonical-dependency-graph.json": report["edges"],
               "canonical-unresolved-imports.json": report["unresolved_imports"],
               "canonical-runtime-dependencies.json": report["runtime_dependencies"]}
    for name, content in outputs.items():
        (out / name).write_text(encode_json(content), encoding="utf-8")
    (out / "canonical-closure.txt").write_text("\n".join(item["path"] for item in report["files"]) + "\n", encoding="utf-8")
    (out / "canonical-manifest.sha256").write_text(report["manifest_sha256"] + "  canonical-manifest.json\n", encoding="utf-8")
    print(f"CANONICAL_ROOT: {report['root']}")
    print(f"CLOSURE_FILE_COUNT: {len(report['files'])}")
    print(f"CLOSURE_MANIFEST_HASH: {report['manifest_sha256']}")
    print(f"UNRESOLVED_IMPORTS: {len(report['unresolved_imports'])}")
    print(f"SOURCE_IMPORT_RESOLUTION: {report['closure_status']}")
    print("CANONICAL_PRODUCTION_CLOSURE: NOT_PROVEN")
    return status


if __name__ == "__main__":
    sys.exit(main())
