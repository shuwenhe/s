#!/usr/bin/env python3
"""Install a private versioned S tree; never overwrite an unrelated command."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MARKER = '.s-installation.json'
TREES = ('src', 'doc', 'examples', 'misc', 'test', 'lib')


def top_level_file(path):
    return path.is_file() and (path.name in ('makefile', 'VERSION', 'BUILD-INFO', 'LICENSE', 'NOTICE')
                               or path.name.endswith('.md'))


def install_files():
    paths = [path for path in ROOT.iterdir() if top_level_file(path)]
    for name in TREES:
        tree = ROOT / name
        if tree.is_symlink():
            raise RuntimeError('installation input symlinks are not supported: ' + str(tree))
        for path in tree.rglob('*'):
            if path.is_symlink():
                raise RuntimeError('installation input symlinks are not supported: ' + str(path))
            if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
                paths.append(path)
    return sorted(paths)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def owned(command, releases):
    if not command.is_symlink():
        raise RuntimeError('refusing to replace or remove an unowned command: ' + str(command))
    target = command.resolve()
    release = target.parent.parent
    if release.parent != releases or target != release / 'bin/s' or not (release / MARKER).is_file():
        raise RuntimeError('command does not point to an S-managed installation: ' + str(command))
    return release


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, default=Path.home() / '.local')
    parser.add_argument('--bin-dir', type=Path)
    parser.add_argument('--uninstall', action='store_true')
    args = parser.parse_args()
    prefix = args.prefix.expanduser().resolve()
    releases = prefix / 'lib/s'
    bin_dir = args.bin_dir.expanduser().resolve() if args.bin_dir else prefix / 'bin'
    command = bin_dir / 's'
    previous = None
    if command.exists() or command.is_symlink():
        previous = owned(command, releases)
    if args.uninstall:
        if previous is None:
            raise RuntimeError('no S-managed command installed at ' + str(command))
        command.unlink()
        shutil.rmtree(previous)
        print('Uninstalled ' + str(previous) + '; other installed versions are retained')
        return
    compiler = ROOT / 'bin/s_compiler'
    if not compiler.is_file() or not os.access(compiler, os.X_OK):
        raise RuntimeError('compiler binary missing; run make compiler or extract a complete binary distribution')
    revision = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    version = ((ROOT / 'VERSION').read_text().strip() if (ROOT / 'VERSION').is_file()
               else 'dev-' + (revision.stdout.strip()[:9] or 'unknown'))
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', version):
        raise RuntimeError('invalid VERSION')
    # Every installed source matters: a library-only upgrade must switch trees.
    fingerprint = hashlib.sha256(compiler.read_bytes())
    inputs = install_files()
    for path in inputs:
        if path.is_symlink():
            raise RuntimeError('installation input symlinks are not supported: ' + str(path))
        fingerprint.update(str(path.relative_to(ROOT)).encode() + b'\0' + path.read_bytes() + b'\0')
    identity = fingerprint.hexdigest()
    destination = releases / (version + '-' + identity[:16])
    releases.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        staging = Path(tempfile.mkdtemp(prefix='.install-', dir=releases))
        try:
            for name in TREES:
                if (ROOT / name).is_dir():
                    shutil.copytree(ROOT / name, staging / name, symlinks=True,
                                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
            for path in ROOT.iterdir():
                if top_level_file(path):
                    shutil.copy2(path, staging / path.name)
            (staging / 'bin').mkdir()
            shutil.copy2(compiler, staging / 'bin/s_compiler')
            shutil.copy2(ROOT / 'misc/scripts/s-driver.sh', staging / 'bin/s')
            (staging / 'bin/s').chmod(0o755)
            if not (staging / 'VERSION').exists():
                (staging / 'VERSION').write_text(version + '\n')
            if not (staging / 'BUILD-INFO').exists():
                revision = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'],
                                          capture_output=True, text=True)
                (staging / 'BUILD-INFO').write_text('source-revision ' + (revision.stdout.strip() or 'unknown') + '\ncertification NOT CERTIFIED\n')
            (staging / MARKER).write_text(json.dumps({'version': version, 'identity': identity,
                                                      'compiler_sha256': digest(compiler)}, indent=2) + '\n')
            staging.rename(destination)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    elif not (destination / MARKER).is_file():
        raise RuntimeError('refusing to reuse an unowned installation directory')
    # Verify before switching the command, including when reusing a version.
    if digest(destination / 'bin/s_compiler') != digest(compiler):
        raise RuntimeError('installed compiler checksum differs')
    if digest(destination / 'bin/s') != digest(ROOT / 'misc/scripts/s-driver.sh'):
        raise RuntimeError('installed driver checksum differs')
    for path in inputs:
        if digest(destination / path.relative_to(ROOT)) != digest(path):
            raise RuntimeError('installed source checksum differs: ' + str(path.relative_to(ROOT)))
    temporary = bin_dir / ('.s-link-' + str(os.getpid()))
    try:
        temporary.symlink_to(os.path.relpath(destination / 'bin/s', bin_dir))
        temporary.replace(command)
    finally:
        if temporary.is_symlink():
            temporary.unlink()
    print('Installed ' + str(command) + ' -> ' + str(destination))
    if previous and previous != destination:
        print('Previous version retained at ' + str(previous))


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError) as error:
        raise SystemExit('s install: ' + str(error))
