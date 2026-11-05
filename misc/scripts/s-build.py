#!/usr/bin/env python3
"""Resolve S source packages, then invoke only the canonical native compiler."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--single-entry', action='store_true', help='standalone executable-file test')
    args = parser.parse_args()
    root = args.root.resolve()
    entry = args.input.resolve(strict=True)
    output = Path(os.path.abspath(args.output))
    compiler = root / 'bin/s_compiler'
    # Source checkouts and accepted immutable inputs must not acquire pycache.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('s_source_imports', root / 'src/cmd/dist/source_imports.py')
    scanner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(scanner)

    def package(path):
        tokens = iter(scanner.source_tokens(path.read_text()))
        for token in tokens:
            if token != 'package':
                continue
            name = next(tokens, '')
            while next(tokens, '') == '.':
                name += '.' + next(tokens, '')
            return name
        return ''

    def production(path):
        return not path.name.endswith('_test.s') and 'testdata' not in path.parts

    library = None

    def resolve(module):
        nonlocal library
        if not module or any(not part.isidentifier() for part in module.split('.')):
            raise ValueError('unsupported import path: ' + module)
        if not module.startswith('std.'):
            relative = Path(*module.split('.'))
            for project in dict.fromkeys((entry.parent, Path.cwd())):
                candidates = []
                candidate = project / relative.with_suffix('.s')
                if candidate.is_file():
                    candidates.append(candidate)
                directory = project / relative
                if directory.is_dir():
                    candidates.extend(sorted(p for p in directory.glob('*.s') if production(p)))
                matches = sorted({p.resolve() for p in candidates if package(p) == module})
                if matches:
                    return matches
        if library is None:
            library = {}
            for path in sorted((root / 'src').rglob('*.s')):
                if production(path):
                    library.setdefault(package(path), []).append(path.resolve())
        if module not in library:
            raise ValueError('unresolved import: ' + module)
        return library[module]

    pending, sources, seen = [entry], [], set()
    if not args.single_entry:
        entry_package = package(entry)
        pending.extend(p.resolve() for p in sorted(entry.parent.glob('*.s'))
                       if p.resolve() != entry and production(p) and package(p) == entry_package)
    cursor = 0
    has_imports = False
    while cursor < len(pending):
        path = pending[cursor]
        cursor += 1
        if path in seen:
            continue
        seen.add(path)
        sources.append(path)
        for module in scanner.imports(path.read_text()):
            has_imports = True
            pending.extend(resolve(module))
    for source in sources:
        if source == output or (output.exists() and source.samefile(output)):
            raise ValueError('output must not overwrite input source: ' + str(source))
    if not has_imports and len(sources) == 1:
        return subprocess.run([str(compiler), 'build', str(entry), str(output)]).returncode
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.s-build-', dir=output.parent) as temporary:
        assembly = Path(temporary) / 'unit.sasm'
        result = subprocess.run([str(compiler), '--compile-unit', str(assembly), *map(str, sources)])
        if result.returncode:
            return result.returncode
        return subprocess.run([str(compiler), '--emit-bin', str(assembly), str(output)]).returncode


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, IndexError, UnicodeError) as error:
        raise SystemExit('s build: ' + str(error))
