#!/usr/bin/env python3
"""Fresh measured Seed -> Stage1 -> Stage2 -> Stage3 with byte convergence.

Run from the preserved checkout. --resume only reuses hash-verified successful
checkpoints; failed/partial attempts are retained separately before retry.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import resource
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]

def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def atomic_json(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    if not args.resume and out.exists() and any(out.iterdir()):
        raise RuntimeError('fresh output directory must be empty')
    out.mkdir(parents=True, exist_ok=True)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)
    if dirty:
        raise RuntimeError('commit the preserved source before bootstrap: ' + dirty)
    files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    inputs = {p: digest(ROOT / p) for p in files if p and (ROOT / p).is_file() and not p.startswith('bin/')}
    snapshot = {'head': head, 'root': str(ROOT), 'files': inputs}
    snapshot_file = out / 'source-manifest.json'
    if args.resume:
        if json.loads(snapshot_file.read_text()) != snapshot:
            raise RuntimeError('preserved source or HEAD changed; checkpoint reuse forbidden')
    else:
        atomic_json(snapshot_file, snapshot)
    results_file = out / 'results.json'
    results = json.loads(results_file.read_text()) if args.resume and results_file.exists() else []
    env = os.environ | {'S_SOURCE_ROOT': str(ROOT), 'S_CANONICAL_TRACE': '1'}

    def limits():
        resource.setrlimit(resource.RLIMIT_AS, (12 * 1024**3,) * 2)
        resource.setrlimit(resource.RLIMIT_CPU, (7200, 7200))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    def unchanged():
        changed = [p for p, sha in inputs.items() if digest(ROOT / p) != sha]
        if changed:
            raise RuntimeError('frozen inputs changed: ' + repr(changed))

    def run(name, command, outputs=()):
        command = list(map(str, command))
        outputs = [Path(p).resolve() for p in outputs]
        previous = next((r for r in results if r['phase'] == name and r['exit'] == 0), None)
        if args.resume and previous:
            if previous['command'] != command or any(not p.exists() or digest(p) != previous['artifacts'].get(str(p)) for p in outputs):
                raise RuntimeError('checkpoint identity/hash mismatch: ' + name)
            return
        paths = [out / (name + suffix) for suffix in ['.log', '.time', '.rss.tsv']] + outputs
        existing = [p for p in paths if p.exists()]
        if existing:
            archived = out / 'attempts' / (name + '-' + str(time.time_ns()))
            archived.mkdir(parents=True)
            for path in existing:
                path.rename(archived / path.name)
        started = time.monotonic()
        rss_peak = 0
        reason = ''
        timefile = out / (name + '.time')
        launched = ['/usr/bin/time', '-v', '-o', str(timefile), *command]
        with (out / (name + '.log')).open('w') as log, (out / (name + '.rss.tsv')).open('w', buffering=1) as samples:
            samples.write('elapsed_seconds\tprocesses\ttree_RSS_kB\ttree_CPU_ticks\n')
            process = subprocess.Popen(launched, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, preexec_fn=limits)
            identity = Path(f'/proc/{process.pid}/stat').read_text().split()[21]
            atomic_json(out / 'active.json', {'phase': name, 'pid': process.pid, 'process_start_ticks': identity, 'command': command, 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
            while process.poll() is None:
                pending, resident, cpu, seen = [process.pid], 0, 0, set()
                while pending:
                    pid = pending.pop()
                    if pid in seen:
                        continue
                    seen.add(pid)
                    try:
                        status = Path(f'/proc/{pid}/status').read_text()
                        stat = Path(f'/proc/{pid}/stat').read_text().split()
                        cpu += int(stat[13]) + int(stat[14])
                        resident += next((int(line.split()[1]) for line in status.splitlines() if line.startswith('VmRSS:')), 0)
                        pending.extend(map(int, Path(f'/proc/{pid}/task/{pid}/children').read_text().split()))
                    except FileNotFoundError:
                        pass
                rss_peak = max(rss_peak, resident)
                samples.write(f'{time.monotonic()-started:.1f}\t{len(seen)}\t{resident}\t{cpu}\n')
                if resident > 4 * 1024**2:
                    reason = 'process-tree RSS exceeded 4 GiB'
                    # The controller owns this new session. Verify PID start time
                    # and session ownership before signalling its process group.
                    if Path(f'/proc/{process.pid}/stat').read_text().split()[21] == identity and os.getpgid(process.pid) == process.pid:
                        os.killpg(process.pid, signal.SIGTERM)
                    break
                time.sleep(2)
            code = process.wait()
        record = {'phase': name, 'exit': code, 'command': command, 'cwd': str(ROOT), 'wall_seconds': time.monotonic()-started, 'sampled_tree_peak_rss_kb': rss_peak, 'artifacts': {str(p): digest(p) for p in outputs if p.exists()}, 'limitation': reason}
        results.append(record)
        atomic_json(results_file, results)
        if code != 0 or reason:
            raise RuntimeError(f'{name}: exit {code}; {reason}; see {name}.log')
        if len(record['artifacts']) != len(outputs):
            raise RuntimeError('successful command missing expected artifact: ' + name)
        unchanged()

    try:
        run('seed-build', ['make', '-B', 'seed-compiler-bin'], [ROOT / 'bin/s_seed'])
        seed = out / 'trusted-seed'
        if not seed.exists():
            shutil.copy2(ROOT / 'bin/s_seed', seed)
        if digest(seed) != digest(ROOT / 'bin/s_seed'):
            raise RuntimeError('trusted Seed identity changed')
        closure = out / 'sources'
        run('source-closure', ['bash', 'src/cmd/dist/source_closure.sh', 'src/cmd/compile/main.s', closure], [closure])
        sources = closure.read_text().splitlines()
        if len(sources) != 268 or len(set(sources)) != 268:
            raise RuntimeError('expected complete unique 268-source closure')
        source_hashes = {p: digest(ROOT / p) for p in sources}
        atomic_json(out / 'closure-sha256.json', source_hashes)
        run('seed-compile', [seed, '--compile-native-unit', out / 'stage1.ir', *sources], [out / 'stage1.ir'])
        run('seed-emit', [seed, '--emit-standalone-amd64', out / 'stage1.ir', out / 'stage1'], [out / 'stage1'])
        for stage in [1, 2, 3]:
            binary = out / f'stage{stage}'
            if stage > 1:
                producer = out / f'stage{stage-1}'
                assembly = out / f'stage{stage}.sasm'
                run(f'stage{stage}-compile', [producer, '--compile-unit', assembly, *sources], [assembly])
                if not assembly.read_bytes().startswith(b'# S-NATIVE-AMD64-V1\n'):
                    raise RuntimeError('wrong native assembly format')
                run(f'stage{stage}-emit', [producer, '--emit-bin', assembly, binary], [binary])
            run(f'stage{stage}-verify', ['sh', 'misc/scripts/verify_true_selfhost.sh', binary])
            run(f'stage{stage}-execution', ['bash', 'src/cmd/dist/checks/selfhost-execution.sh', binary, out / f'stage{stage}-execution'])
            run(f'stage{stage}-strict-type', ['python3', 'test/native-bootstrap-diagnostic/native_type_identity_check.py', ROOT, binary])
            run(f'stage{stage}-gc', ['python3', 'test/native-bootstrap-diagnostic/native_gc_check.py', binary])
            run(f'stage{stage}-object', ['python3', 'test/native-bootstrap-diagnostic/native_gc_object_check.py', binary])
        if (out / 'stage2.sasm').read_bytes() != (out / 'stage3.sasm').read_bytes():
            raise RuntimeError('Stage2/Stage3 assembly bytes differ')
        if (out / 'stage2').read_bytes() != (out / 'stage3').read_bytes():
            raise RuntimeError('Stage2/Stage3 executable bytes differ')
        atomic_json(out / 'convergence.json', {'definition': 'exact assembly and ELF bytes; no normalization', 'assembly_sha256': digest(out / 'stage2.sasm'), 'binary_sha256': digest(out / 'stage2')})
        # Preserve any existing usable compiler before installing the verified one.
        compiler = ROOT / 'bin/s_compiler'
        if compiler.exists() and not (out / 'previous-compiler').exists():
            shutil.copy2(compiler, out / 'previous-compiler')
        shutil.copy2(out / 'stage3', compiler)
        generated = ROOT / '.bootstrap/compiler'
        generated.mkdir(parents=True, exist_ok=True)
        shutil.copy2(out / 'stage1.ir', generated / 'compiler.ir')
        run('production', ['make', '-o', 'compiler', 'selfhost-canonical-production-check'])
        if digest(compiler) != digest(out / 'stage3'):
            raise RuntimeError('production suite replaced final compiler')
        unchanged()
        atomic_json(out / 'artifacts-sha256.json', {p.name: digest(p) for p in [seed, out/'stage1.ir', out/'stage1', out/'stage2.sasm', out/'stage2', out/'stage3.sasm', out/'stage3']})
        (out / '.accepted').write_text('all bootstrap, convergence, source identity and production gates passed\n')
        (out / 'active.json').unlink(missing_ok=True)
    except BaseException as error:
        atomic_json(out / 'FAILED.json', {'error': repr(error), 'head': head})
        raise

if __name__ == '__main__':
    main()
