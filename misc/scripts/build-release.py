#!/usr/bin/env python3
"""Create deterministic private candidates or locally certified S artifacts."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
GATES = ('source', 'seed', 'stage1', 'stage2', 'stage3', 'stage3_selfcompile', 'convergence', 'production')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def accepted_compiler(evidence, revision, entries):
    if not (ROOT / 'LICENSE').is_file() or not (ROOT / 'LICENSE').read_text().strip():
        raise RuntimeError('official distribution requires an owner-approved LICENSE')
    report = json.loads((evidence / 'ACCEPTED.json').read_text())
    if report.get('revision') != revision or report.get('mode') != 'full' or report.get('checkpoint_reuse') is not False:
        raise RuntimeError('full fresh acceptance must match the exact release revision')
    if report.get('status') != dict.fromkeys(GATES, 'PASS'):
        raise RuntimeError('every required acceptance gate must PASS')
    if not report.get('commands') or any(c.get('exit') != 0 for c in report['commands']):
        raise RuntimeError('missing or failed acceptance command receipts')
    source = json.loads((evidence / 'source-manifest.json').read_text())
    if source.get('revision') != revision or set(source.get('files', {})) != set(entries):
        raise RuntimeError('release source inventory differs from acceptance')
    for name, (data, mode) in entries.items():
        if source['files'][name]['sha256'] != hashlib.sha256(data).hexdigest():
            raise RuntimeError('release source differs from acceptance: ' + name)
        if source['files'][name].get('executable') != bool(mode & 0o111):
            raise RuntimeError('accepted executable mode differs from committed source: ' + name)
    hashes = report.get('artifact_sha256', {})
    required = ('seed', 'stage1', 'stage1.ir', 'stage2', 'stage2.sasm', 'stage3', 'stage3.sasm',
                'stage3-rebuild', 'stage3-rebuild.sasm')
    for name in required:
        if hashes.get(name) != digest(evidence / 'build' / name):
            raise RuntimeError('accepted artifact hash differs: ' + name)
    for names in (('stage2', 'stage3', 'stage3-rebuild'), ('stage2.sasm', 'stage3.sasm', 'stage3-rebuild.sasm')):
        if len({hashes[name] for name in names}) != 1:
            raise RuntimeError('accepted artifacts do not converge')
    return evidence / 'build/stage3'


def archive(path, prefix, entries, epoch):
    # Normalize metadata, order and gzip header; retain committed executable bits.
    with path.open('xb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as stream:
            for name, (data, mode) in sorted(entries.items()):
                info = tarfile.TarInfo(prefix + '/' + name)
                info.size = len(data)
                info.mode = mode
                info.mtime = epoch
                stream.addfile(info, io.BytesIO(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--candidate', action='store_true', help='private, explicitly uncertified artifact')
    mode.add_argument('--acceptance', type=Path, help='same-revision full clean-room evidence directory')
    parser.add_argument('--compiler', type=Path, help='candidate compiler; certified artifacts always use accepted Stage3')
    args = parser.parse_args()
    if args.output.exists():
        raise RuntimeError('output exists; choose a new directory to preserve evidence')
    if git('status', '--porcelain', '--untracked-files=all').strip():
        raise RuntimeError('commit all release sources before packaging')
    revision = git('rev-parse', 'HEAD').decode().strip()
    epoch = int(git('show', '-s', '--format=%ct', 'HEAD'))
    entries = {}
    with tarfile.open(fileobj=io.BytesIO(git('archive', '--format=tar', revision))) as stream:
        for member in stream:
            if member.isdir():
                continue
            if not member.isfile():
                raise RuntimeError('release source symlinks need an explicit packaging policy: ' + member.name)
            data = stream.extractfile(member).read()
            if (ROOT / member.name).is_symlink() or (ROOT / member.name).read_bytes() != data:
                raise RuntimeError('worktree bytes differ from committed source: ' + member.name)
            entries[member.name] = (data, 0o755 if member.mode & 0o111 else 0o644)
    version = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', version):
        raise RuntimeError('invalid VERSION')
    compiler = (args.compiler or ROOT / 'bin/s_compiler').resolve()
    certification = 'NOT CERTIFIED'
    if args.acceptance:
        if args.compiler:
            raise RuntimeError('--compiler is only permitted for private candidates')
        compiler = accepted_compiler(args.acceptance.resolve(), revision, entries)
        certification = 'LOCAL FULL BOOTSTRAP; independent release CI still required'
    binary = compiler.read_bytes()
    if not binary.startswith(b'\x7fELF\x02\x01') or int.from_bytes(binary[18:20], 'little') != 62:
        raise RuntimeError('compiler must be a Linux/amd64 ELF64 binary')
    source_entries = entries.copy()
    entries['bin/s'] = ((ROOT / 'misc/scripts/s-driver.sh').read_bytes(), 0o755)
    entries['bin/s_compiler'] = (binary, 0o755)
    info = ('source-revision ' + revision + '\ncompiler-sha256 ' + digest(compiler)
            + '\ncertification ' + certification + '\ntarget linux/amd64\n')
    entries['BUILD-INFO'] = (info.encode(), 0o644)
    checksums = ''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
                        for name, (data, _) in sorted(entries.items()))
    entries['FILES.sha256'] = (checksums.encode(), 0o644)
    label = 's-' + version + ('-candidate' if args.candidate else '')
    args.output.mkdir(parents=True, exist_ok=False)
    archive(args.output / (label + '-linux-amd64.tar.gz'), label, entries, epoch)
    archive(args.output / (label + '-source.tar.gz'), label + '-source', source_entries, epoch)
    manifest = {'version': version, 'revision': revision, 'target': 'linux/amd64',
                'compiler_sha256': digest(compiler), 'certification': certification,
                'source_date_epoch': epoch,
                'artifacts': {p.name: digest(p) for p in sorted(args.output.glob('*.tar.gz'))}}
    (args.output / 'release.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    (args.output / 'SHA256SUMS').write_text(''.join(digest(p) + '  ' + p.name + '\n'
                                           for p in sorted(args.output.iterdir()) if p.is_file()))
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit('s release: ' + str(error))
