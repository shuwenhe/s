#!/usr/bin/env python3
"""Build an exact committed revision in a new checkout; never resume or reuse stages."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


GIT_SETTINGS = ['-c', 'core.autocrlf=false', '-c', 'core.eol=lf',
                '-c', 'core.attributesFile=/dev/null', '-c', 'core.hooksPath=/dev/null']


def git_environment():
    return {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'GIT_CONFIG_NOSYSTEM': '1',
            'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_ATTR_NOSYSTEM': '1'}


def git_bytes(root, *args):
    return subprocess.check_output(['git', *GIT_SETTINGS, '-C', str(root), *args], env=git_environment())


def git(root, *args):
    return git_bytes(root, *args).decode().strip()


def fresh_directory(path):
    path = Path(path)
    if path.exists() or path.is_symlink():
        raise FileExistsError('output already exists; choose a fresh directory: ' + str(path))
    path.mkdir(parents=True)


def create_checkout(repository, revision, destination):
    repository, destination = Path(repository).resolve(), Path(destination)
    if git(repository, 'status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('repository must be clean; commit required sources first')
    revision = git(repository, 'rev-parse', revision + '^{commit}')
    if destination.exists():
        raise FileExistsError('checkout already exists: ' + str(destination))
    subprocess.run(['git', *GIT_SETTINGS, 'clone', '--no-local', '--no-hardlinks', '--no-checkout', str(repository), str(destination)], check=True, capture_output=True, env=git_environment())
    subprocess.run(['git', *GIT_SETTINGS, '-C', str(destination), 'checkout', '--detach', revision], check=True, capture_output=True, env=git_environment())
    if git(destination, 'rev-parse', 'HEAD') != revision:
        raise RuntimeError('clone revision mismatch')
    if (destination / '.git/objects/info/alternates').exists():
        raise RuntimeError('clone unexpectedly shares object storage')
    verify_committed_blobs(destination, revision)
    return revision


def source_manifest(root):
    paths = git_bytes(root, 'ls-files', '-z').decode().split('\0')
    result = {}
    for name in paths:
        if not name:
            continue
        path = Path(root) / name
        if path.is_symlink():
            result[name] = {'symlink': os.readlink(path)}
        else:
            result[name] = {'sha256': digest(path), 'executable': bool(path.stat().st_mode & 0o111)}
    return result


def verify_committed_blobs(root, revision):
    for item in git_bytes(root, 'ls-tree', '-r', '-z', revision).split(b'\0'):
        if not item:
            continue
        metadata, name = item.split(b'\t', 1)
        mode, kind, expected = metadata.decode().split()
        if kind != 'blob':
            raise RuntimeError('unsupported committed input kind: ' + name.decode())
        path = Path(root) / name.decode()
        data = os.readlink(path).encode() if mode == '120000' else path.read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if actual != expected:
            raise RuntimeError('checkout differs from committed blob: ' + str(path))
        if mode != '120000' and bool(path.stat().st_mode & 0o111) != (mode == '100755'):
            raise RuntimeError('checkout mode differs from committed mode: ' + str(path))


def mark_failure(statuses, phase):
    statuses[phase] = 'FAIL'


def verify_sources(root, revision, manifest):
    if git(root, 'rev-parse', 'HEAD') != revision:
        raise RuntimeError('frozen source revision changed')
    if git(root, 'status', '--porcelain', '--untracked-files=all'):
        raise RuntimeError('frozen source worktree changed')
    if source_manifest(root) != manifest:
        raise RuntimeError('frozen source manifest changed')


def prepare_host_tools(directory, inherited=None):
    """Pin the regression suite's ripgrep without inheriting unrelated host PATHs."""
    inherited = os.environ if inherited is None else inherited
    candidate = shutil.which('rg', path=inherited.get('PATH', '/usr/bin:/bin'))
    if candidate is None:
        raise RuntimeError('required production dependency missing: rg (ripgrep)')
    source = Path(candidate).resolve()
    expected = digest(source)
    fresh_directory(directory)
    target = Path(directory) / 'rg'
    shutil.copy2(source, target)
    if digest(target) != expected:
        raise RuntimeError('host ripgrep changed while being pinned')
    return {'rg': {'source': str(source), 'path': str(target), 'sha256': expected}}


def clean_environment(root, temporary, inherited=None, host_tools=None):
    # Deliberate allowlist: no S_*, MAKEFLAGS, CC, CFLAGS, preload, runner or caches.
    temporary = Path(temporary)
    temporary.mkdir(parents=True, exist_ok=True)
    path = '/usr/bin:/bin' if host_tools is None else str(host_tools) + ':/usr/bin:/bin'
    return {'PATH': path, 'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC',
            'TMPDIR': str(temporary), 'S_SOURCE_ROOT': str(root),
            'S_TARGET_OS': 'linux', 'S_TARGET_ARCH': 'amd64',
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null'}


def compare_artifacts(left, right):
    if Path(left).read_bytes() != Path(right).read_bytes():
        raise RuntimeError('artifact convergence failed; bytes differ: ' + str(left) + ' versus ' + str(right))
    return digest(left)


def function_labels(assembly):
    if not assembly.startswith('# S-NATIVE-AMD64-V1\n'):
        raise RuntimeError('missing native assembly version')
    if not re.search(r'^_start:$', assembly, re.M) or not re.search(r'^s_native_entry:$', assembly, re.M):
        raise RuntimeError('missing compiler start/entry point')
    labels = re.findall(r'^(s_native_fn_\d+):$', assembly, re.M)
    if not labels or len(labels) != len(set(labels)):
        raise RuntimeError('missing or duplicate native function labels')
    referenced = set(re.findall(r'\bs_native_fn_\d+\b', assembly))
    if referenced != set(labels):
        raise RuntimeError('undefined native function labels: ' + repr(sorted(referenced - set(labels))))
    return sorted(labels, key=lambda name: int(name.rsplit('_', 1)[1]))


def expected_functions(mir):
    """Independent graph oracle for the frozen public MIR format, before SSA pruning."""
    header = re.match(r'mir-program-v1 package=\S+ entry=(\S+)\n', mir)
    if not header:
        raise RuntimeError('malformed public MIR header')
    entry = header.group(1)
    functions, external, parameters, results = [], {}, {}, {}
    instruction_edges, table_edges = set(), set()
    current = None
    for line in mir.splitlines()[1:]:
        match = re.fullmatch(r'function (\S+) external=(true|false)', line)
        if match:
            current = match.group(1)
            if current in external:
                raise RuntimeError('duplicate MIR function: ' + current)
            functions.append(current)
            external[current] = match.group(2) == 'true'
            parameters[current] = 0
        elif line.startswith('parameter ') and current:
            parameters[current] += 1
        elif line.startswith('results ') and current:
            results[current] = line[8:]
        elif line.startswith('instruction call '):
            target = re.search(r' symbol=(\S+)$', line)
            if current is None or target is None:
                raise RuntimeError('malformed MIR call instruction')
            instruction_edges.add((current, target.group(1)))
        elif line.startswith('call '):
            edge = re.fullmatch(r'call (\S+) -> (\S+) block=\d+ instruction=\d+', line)
            if not edge:
                raise RuntimeError('malformed MIR call table')
            table_edges.add((edge.group(1), edge.group(2)))
    if entry not in external or external[entry]:
        raise RuntimeError('missing MIR entry body')
    if instruction_edges != table_edges:
        raise RuntimeError('MIR call instruction/table disagreement')
    if any(caller not in external or callee not in external for caller, callee in table_edges):
        raise RuntimeError('MIR call references missing function')
    # Frozen program_environment.s creates exactly this reserved initializer prefix.
    initializers = [name for name in functions if '.__global_init_' in name]
    if any(external[name] or parameters[name] != 0 or not results.get(name) for name in initializers):
        raise RuntimeError('invalid global initializer signature')
    edges = {name: [] for name in functions}
    for caller, callee in sorted(table_edges):
        edges[caller].append(callee)
    pending, live = [entry, *initializers], set()
    while pending:
        name = pending.pop()
        if name in live:
            continue
        if external[name]:
            raise RuntimeError('unresolved reachable external in MIR: ' + name)
        live.add(name)
        pending.extend(edges[name])
    retained = [name for name in functions if name in live]
    return {'entry': entry, 'initializers': initializers, 'functions': retained,
            'calls': {name: edges[name] for name in retained},
            'root_rule': 'entry plus reserved .__global_init_ functions from frozen program_environment.s',
            'ordering': 'original MIR function order filtered by independent direct-call reachability'}


def verify_expected_functions(assembly, expected):
    functions = expected['functions']
    labels = function_labels(assembly)
    inventory = ['s_native_fn_' + str(index) for index in range(len(functions))]
    if labels != inventory:
        raise RuntimeError('native inventory differs from independently expected MIR functions')
    entry = re.search(r'^s_native_entry:\n\s+jmp (s_native_fn_\d+)\n', assembly, re.M)
    if not entry or entry.group(1) != inventory[functions.index(expected['entry'])]:
        raise RuntimeError('native entry differs from expected MIR entry')
    for index, name in enumerate(functions):
        label = inventory[index]
        body = re.search(r'^' + label + r':\n(.*?)^\.size\s+' + label + ',', assembly, re.M | re.S)
        if not body:
            raise RuntimeError('missing native function extent: ' + label)
        actual = {functions[int(target)] for target in re.findall(r'\bcall\s+s_native_fn_(\d+)\b', body.group(1))}
        if actual != set(expected['calls'][name]):
            raise RuntimeError('native call edges differ from MIR: ' + name)
    if expected['initializers']:
        body = re.search(r'^s_native_initialize_globals:\n(.*?)^\.size\s+s_native_initialize_globals,', assembly, re.M | re.S)
        if not body:
            raise RuntimeError('missing native global initialization entry')
        actual = {functions[int(target)] for target in re.findall(r'\bcall\s+s_native_fn_(\d+)\b', body.group(1))}
        if actual != set(expected['initializers']):
            raise RuntimeError('native global initializer roots differ from MIR')
    return labels


def production_inventory(root, stdout):
    lines = (Path(root) / 'makefile').read_text().splitlines()
    expected = []
    pattern = r'\btest/[A-Za-z0-9_./-]+\.(?:sh|py)\b'
    for target in ['selfhost-canonical-parser-check', 'selfhost-canonical-production-check']:
        start = next(i for i, line in enumerate(lines) if line.startswith(target + ':')) + 1
        for line in lines[start:]:
            if line and not line.startswith('\t'):
                break
            expected.extend(re.findall(pattern, line))
    observed = set(re.findall(pattern, stdout))
    missing = sorted(set(expected) - observed)
    if missing:
        raise RuntimeError('production tests not executed in make trace: ' + repr(missing))
    return {'test_commands': len(expected), 'expected_commands': expected,
            'observed_commands': sorted(observed & set(expected)), 'missing_commands': missing,
            'pass_summaries': sum('PASS' in line for line in stdout.splitlines()),
            'count_definition': 'Executed Makefile test-script recipes, not individual assertions inside scripts'}


class CommandRunner:
    def __init__(self, root, logs, environment, poll_interval=1.0):
        self.root, self.logs, self.environment = Path(root), Path(logs), environment
        self.results = []
        self.poll_interval = poll_interval

    def run(self, name, command, outputs=(), expected=0, trace=False):
        command = list(map(str, command))
        outputs = list(map(Path, outputs))
        receipt = self.logs / (name + '.json')
        if receipt.exists() or any(path.exists() for path in outputs):
            raise RuntimeError('refusing command/output reuse: ' + name)
        stdout_path, stderr_path = [self.logs / (name + suffix) for suffix in ['.stdout.log', '.stderr.log']]
        metrics = self.logs / (name + '.time')
        launched = command
        trace_path = self.logs / (name + '.execve.log')
        if trace:
            launched = ['/usr/bin/strace', '-f', '-qq', '-s', '4096', '-v', '-e', 'trace=execve', '-o', str(trace_path), *command]
        start = time.monotonic()
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        print(name + ': RUNNING', flush=True)
        write_json(self.logs / 'active.json', {'phase': name, 'status': 'RUNNING', 'command': command, 'started_utc': started})
        functions, diagnostics, peak_tree_rss = set(), 0, 0
        log_position, pending_text = 0, ''
        last_console = start
        resources = self.logs / (name + '.resources.tsv')
        with stdout_path.open('x') as stdout, stderr_path.open('x') as stderr, resources.open('x') as samples:
            process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(metrics), *launched], cwd=self.root,
                                       env=self.environment, stdout=stdout, stderr=stderr,
                                       stdin=subprocess.DEVNULL, start_new_session=True)
            samples.write('elapsed_seconds\tprocesses\ttree_rss_kb\ttree_vmdata_kb\tlive_process_cpu_seconds\tMIR_functions\tdiagnostics\n')
            while True:
                process_ids, seen, resident, data, ticks = [process.pid], set(), 0, 0, 0
                while process_ids:
                    pid = process_ids.pop()
                    if pid in seen:
                        continue
                    seen.add(pid)
                    try:
                        proc = Path('/proc') / str(pid)
                        status = (proc / 'status').read_text()
                        values = {line.split(':')[0]: int(line.split()[1]) for line in status.splitlines()
                                  if line.startswith(('VmRSS:', 'VmData:'))}
                        resident += values.get('VmRSS', 0)
                        data += values.get('VmData', 0)
                        fields = (proc / 'stat').read_text().rpartition(')')[2].split()
                        ticks += int(fields[11]) + int(fields[12])
                        process_ids.extend(map(int, (proc / 'task' / str(pid) / 'children').read_text().split()))
                    except (FileNotFoundError, ProcessLookupError):
                        pass
                peak_tree_rss = max(peak_tree_rss, resident)
                with stderr_path.open(errors='replace') as emitted:
                    emitted.seek(log_position)
                    pending_text += emitted.read()
                    log_position = emitted.tell()
                lines = pending_text.split('\n')
                pending_text = lines.pop()
                for line in lines:
                    if line.startswith('canonical: MIR function '):
                        functions.add(line[len('canonical: MIR function '):])
                    if line.startswith(('canonical semantic:', 'canonical parser:', 'mir-error:', 'amd64:')):
                        diagnostics += 1
                elapsed = time.monotonic() - start
                cpu = ticks / os.sysconf('SC_CLK_TCK')
                samples.write(f'{elapsed:.3f}\t{len(seen)}\t{resident}\t{data}\t{cpu:.3f}\t{len(functions)}\t{diagnostics}\n')
                samples.flush()
                if time.monotonic() - last_console >= 60:
                    print(f'{name}: RUNNING elapsed={elapsed:.0f}s RSS={resident}KiB MIR={len(functions)} diagnostics={diagnostics}', flush=True)
                    last_console = time.monotonic()
                write_json(self.logs / 'heartbeat.json', {'phase': name, 'status': 'RUNNING',
                           'pid': process.pid, 'seconds': elapsed, 'tree_rss_kb': resident,
                           'tree_vmdata_kb': data, 'sampled_tree_peak_rss_kb': peak_tree_rss,
                           'cpu_seconds_live': cpu, 'mir_functions_processed': len(functions),
                           'compiler_diagnostics': diagnostics,
                           'updated_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()})
                if process.poll() is not None:
                    break
                time.sleep(self.poll_interval)
            code = process.wait()
        with stderr_path.open(errors='replace') as emitted:
            emitted.seek(log_position)
            remaining = pending_text + emitted.read()
        for line in remaining.splitlines():
            if line.startswith('canonical: MIR function '):
                functions.add(line[len('canonical: MIR function '):])
            if line.startswith(('canonical semantic:', 'canonical parser:', 'mir-error:', 'amd64:')):
                diagnostics += 1
        metrics_text = metrics.read_text()
        rss = re.search(r'Maximum resident set size \(kbytes\): (\d+)', metrics_text)
        failure = ''
        if code != expected:
            failure = 'command exit ' + str(code) + ', expected ' + str(expected)
        elif any(not path.is_file() or path.stat().st_size == 0 for path in outputs):
            failure = 'missing or empty command output'
        if trace and not failure:
            allowed = {str(Path(path).resolve()) for path in
                       [command[0], '/usr/bin/as', '/usr/bin/ld', '/usr/bin/mkdir', '/usr/bin/rm']}
            for line in trace_path.read_text().splitlines():
                match = re.search(r'execve\(("(?:\\.|[^"\\])*")', line)
                if match and re.search(r'= 0\s*$', line):
                    executable = str(Path(json.loads(match.group(1))).resolve())
                    if executable not in allowed:
                        failure = 'unexpected executable at compiler boundary: ' + executable
                        break
        record = {'phase': name, 'status': 'FAIL' if failure else 'PASS', 'command': command,
                  'cwd': str(self.root), 'started_utc': started, 'exit': code,
                  'expected_exit': expected, 'seconds': time.monotonic() - start,
                  'peak_rss_kb': int(rss.group(1)) if rss else None,
                  'sampled_tree_peak_rss_kb': peak_tree_rss,
                  'sampling_definition': 'Live descendant main-thread child lists sampled; live CPU may decrease when children exit. Final GNU time CPU/RSS are authoritative. VmData is mapped data, not cumulative allocator event counts.',
                  'mir_functions_processed': len(functions), 'compiler_diagnostics': diagnostics,
                  'diagnostic_count_rule': 'canonical parser/semantic, mir-error and amd64 error line prefixes',
                  'rss_definition': 'GNU time maximum resident set size of command/descendants (KiB)',
                  'output_sha256': {str(path): digest(path) for path in outputs if path.is_file()},
                  'stdout_sha256': digest(stdout_path), 'stderr_sha256': digest(stderr_path), 'failure': failure}
        for key, label in [('user_seconds', 'User time (seconds)'), ('system_seconds', 'System time (seconds)')]:
            value = re.search(re.escape(label) + r': ([0-9.]+)', metrics_text)
            record[key] = float(value.group(1)) if value else None
        cpu_percent = re.search(r'Percent of CPU this job got: ([0-9.]+)%', metrics_text)
        record['cpu_percent'] = float(cpu_percent.group(1)) if cpu_percent else None
        write_json(receipt, record)
        write_json(self.logs / 'heartbeat.json', {'phase': name, 'status': record['status'],
                   'seconds': record['seconds'], 'peak_rss_kb': record['peak_rss_kb'],
                   'mir_functions_processed': len(functions), 'compiler_diagnostics': diagnostics})
        (self.logs / 'active.json').unlink()
        self.results.append(record)
        write_json(self.logs / 'results.json', self.results)
        print(name + ': ' + record['status'], flush=True)
        if failure:
            raise RuntimeError(name + ': ' + failure)
        return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mode', choices=['full', 'core'], default='full')
    args = parser.parse_args()
    out = args.output.absolute()
    fresh_directory(out)
    evidence = out / 'evidence'; evidence.mkdir()
    logs = evidence / 'logs'; logs.mkdir()
    build = evidence / 'build'; build.mkdir()
    root = out / 'checkout'
    statuses = {name: 'NOT RUN' for name in ['source', 'seed', 'stage1', 'stage2', 'stage3', 'stage3_selfcompile', 'convergence', 'production']}
    active_phase = 'source'
    write_json(evidence / 'status.json', statuses)
    try:
        if platform.system() != 'Linux' or platform.machine() not in ['x86_64', 'amd64']:
            raise RuntimeError('clean-room native acceptance requires Linux/amd64')
        # Explicit, fail-loud dependency detection before any build or test runs.
        # The regression suite (test/native-bootstrap-diagnostic/*.sh) invokes
        # ripgrep (rg) directly, so it is a hard requirement; surface a clear
        # diagnostic here instead of failing deep inside the build.
        for name in ['git', 'gcc', 'cc', 'make', 'as', 'ld', 'strace', 'time', 'bash', 'python3',
                     'nm', 'objdump', 'readelf', 'sha256sum', 'cmp', 'awk', 'sed', 'grep', 'file', 'timeout', 'strings',
                     'tar', 'find', 'xargs', 'sort', 'head', 'tail', 'stat', 'wc', 'cut', 'tr', 'dd', 'mkdir', 'rm', 'cp', 'chmod']:
            path = Path('/usr/bin', name)
            if not path.exists():
                raise RuntimeError('required host tool missing: ' + name)
        host_tools = out / 'host-tools'
        host_tool_manifest = prepare_host_tools(host_tools)
        revision = create_checkout(args.repository, args.revision, root)
        initial = source_manifest(root)
        launcher_hash = digest(Path(__file__))
        if initial['misc/scripts/cleanroom-selfhost.py']['sha256'] != launcher_hash:
            raise RuntimeError('invoking controller differs from frozen committed controller')
        # Preserve executable bits but make all tracked regular input files read-only.
        for name in initial:
            path = root / name
            if not path.is_symlink():
                path.chmod(path.stat().st_mode & ~0o222)
        environment = clean_environment(root, out / 'temporary', host_tools=host_tools)
        environment['S_CANONICAL_TRACE'] = '1'
        runner = CommandRunner(root, logs, environment)
        write_json(evidence / 'source-manifest.json', {'revision': revision, 'files': initial})
        write_json(evidence / 'configuration.json', {'revision': revision, 'mode': args.mode,
                   'target': 'linux/amd64', 'environment': environment, 'platform': platform.platform(),
                   'host_tools': host_tool_manifest,
                   'controller_sha256': launcher_hash,
                   'clean_clone': 'git clone --no-local --no-hardlinks --no-checkout; detached exact revision',
                   'checkpoint_reuse': False, 'stage_transition_execve_audit': True})
        runner.run('toolchain', ['sh', '-c', 'uname -a; gcc --version; as --version; ld --version; make --version; python3 --version; rg --version'])
        runner.run('source-archive', ['git', 'archive', '--format=tar', '-o', evidence / 'source.tar', revision], [evidence / 'source.tar'])
        closure = evidence / 'sources'
        runner.run('source-closure', ['bash', 'src/cmd/dist/source_closure.sh', 'src/cmd/compile/main.s', closure], [closure])
        sources = closure.read_text().splitlines()
        if len(sources) != len(set(sources)) or len(sources) != 268 or any(name not in initial for name in sources):
            raise RuntimeError('expected complete unique tracked 268-source closure')
        closure_hashes = {name: digest(root / name) for name in sources}
        write_json(evidence / 'closure-sha256.json', closure_hashes)
        (evidence / 'source.sha256').write_text(''.join(value + '  ' + name + '\n' for name, value in closure_hashes.items()))
        statuses['source'] = 'PASS'
        active_phase = 'seed'
        runner.run('seed-build', ['make', '-B', 'seed-compiler-bin'], [root / 'bin/s_seed'])
        seed = build / 'seed'; shutil.copy2(root / 'bin/s_seed', seed)
        statuses['seed'] = 'PASS'
        active_phase = 'stage1'
        runner.run('stage1-compile', [seed, '--compile-native-unit', build / 'stage1.ir', *sources], [build / 'stage1.ir'], trace=True)
        runner.run('stage1-emit', [seed, '--emit-standalone-amd64', build / 'stage1.ir', build / 'stage1'], [build / 'stage1'], trace=True)
        final_stage = 3 if args.mode == 'full' else 1
        labels = {}
        expected = None
        for stage in range(1, final_stage + 1):
            active_phase = f'stage{stage}'
            verify_sources(root, revision, initial)
            write_json(evidence / f'stage{stage}-source-sha256.json', {name: digest(root / name) for name in sources})
            if stage > 1:
                producer, assembly, binary = [build / name for name in [f'stage{stage-1}', f'stage{stage}.sasm', f'stage{stage}']]
                runner.run(f'stage{stage}-compile', [producer, '--compile-unit', assembly, *sources], [assembly], trace=True)
                labels[stage] = verify_expected_functions(assembly.read_text(), expected)
                write_json(evidence / f'stage{stage}-functions.json', labels[stage])
                runner.run(f'stage{stage}-emit', [producer, '--emit-bin', assembly, binary], [binary], trace=True)
            binary = build / f'stage{stage}'
            runner.run(f'stage{stage}-verify', ['sh', 'misc/scripts/verify_true_selfhost.sh', binary])
            runner.run(f'stage{stage}-execution', ['bash', 'src/cmd/dist/checks/selfhost-execution.sh', binary, evidence / f'stage{stage}-execution'])
            for name, script, parameters in [('strict-type', 'native_type_identity_check.py', [root, binary]),
                                              ('gc', 'native_gc_check.py', [binary]),
                                              ('object', 'native_gc_object_check.py', [binary])]:
                runner.run(f'stage{stage}-{name}', ['python3', 'test/native-bootstrap-diagnostic/' + script, *parameters])
            verify_sources(root, revision, initial)
            if stage == 1 and args.mode == 'full':
                combined = evidence / 'compiler-source.s'
                combined.write_bytes(b''.join((root / name).read_bytes() + b'\n' for name in sources))
                public_mir = evidence / 'compiler.mir'
                runner.run('stage1-public-mir', [binary, combined, public_mir], [public_mir], trace=True)
                verify_sources(root, revision, initial)
                expected = expected_functions(public_mir.read_text())
                write_json(evidence / 'expected-functions.json', expected)
                write_json(evidence / 'oracle-input-sha256.json', {str(combined): digest(combined), str(public_mir): digest(public_mir)})
            statuses[f'stage{stage}'] = 'PASS'
            write_json(evidence / 'status.json', statuses)
        if args.mode == 'full':
            active_phase = 'stage3_selfcompile'
            rebuilt_assembly, rebuilt_binary = build / 'stage3-rebuild.sasm', build / 'stage3-rebuild'
            verify_sources(root, revision, initial)
            runner.run('stage3-selfcompile', [build / 'stage3', '--compile-unit', rebuilt_assembly, *sources], [rebuilt_assembly], trace=True)
            verify_expected_functions(rebuilt_assembly.read_text(), expected)
            runner.run('stage3-selfemit', [build / 'stage3', '--emit-bin', rebuilt_assembly, rebuilt_binary], [rebuilt_binary], trace=True)
            runner.run('stage3-selfverify', ['sh', 'misc/scripts/verify_true_selfhost.sh', rebuilt_binary])
            runner.run('stage3-selfexecution', ['bash', 'src/cmd/dist/checks/selfhost-execution.sh', rebuilt_binary, evidence / 'stage3-rebuild-execution'])
            compare_artifacts(build / 'stage3.sasm', rebuilt_assembly)
            compare_artifacts(build / 'stage3', rebuilt_binary)
            verify_sources(root, revision, initial)
            statuses['stage3_selfcompile'] = 'PASS'
            active_phase = 'convergence'
            if labels[2] != labels[3]:
                raise RuntimeError('reachable function sets do not converge')
            assembly_hash = compare_artifacts(build / 'stage2.sasm', build / 'stage3.sasm')
            binary_hash = compare_artifacts(build / 'stage2', build / 'stage3')
            for stage in [1, 2, 3]:
                if json.loads((evidence / f'stage{stage}-source-sha256.json').read_text()) != closure_hashes:
                    raise RuntimeError('stage source manifests differ')
            write_json(evidence / 'convergence.json', {'status': 'PASS', 'comparison': 'exact bytes; no normalization',
                       'assembly_sha256': assembly_hash, 'executable_sha256': binary_hash,
                       'reachable_functions': len(labels[2]), 'source_manifests_identical': True})
            statuses['convergence'] = 'PASS'
        expected_outputs = {'seed', 'stage1.ir', 'stage1'}
        if args.mode == 'full':
            expected_outputs.update({'stage2.sasm', 'stage2', 'stage3.sasm', 'stage3', 'stage3-rebuild.sasm', 'stage3-rebuild'})
        if {path.name for path in build.iterdir()} != expected_outputs:
            raise RuntimeError('unexpected missing or extra bootstrap output')
        shutil.copy2(build / f'stage{final_stage}', root / 'bin/s_compiler')
        generated = root / '.bootstrap/compiler'; generated.mkdir(exist_ok=True, parents=True)
        shutil.copy2(build / 'stage1.ir', generated / 'compiler.ir')
        compiler_hash = digest(root / 'bin/s_compiler')
        active_phase = 'production'
        runner.run('production', ['make', '--trace', '-o', 'compiler', 'selfhost-canonical-production-check'])
        production_tests = production_inventory(root, (logs / 'production.stdout.log').read_text())
        write_json(evidence / 'production-test-inventory.json', production_tests)
        if digest(root / 'bin/s_compiler') != compiler_hash:
            raise RuntimeError('production suite replaced accepted compiler')
        verify_sources(root, revision, initial)
        statuses['production'] = 'PASS'
        write_json(evidence / 'artifact-sha256.json', {p.name: digest(p) for p in sorted(build.iterdir())})
        write_json(evidence / 'source-manifest.after.json', {'revision': revision, 'files': source_manifest(root)})
        write_json(evidence / 'status.json', statuses)
        write_json(evidence / ('ACCEPTED.json' if args.mode == 'full' else 'CORE-PASSED.json'),
                   {'revision': revision, 'mode': args.mode, 'status': statuses, 'checkpoint_reuse': False,
                    'production_tests': production_tests, 'commands': runner.results,
                    'artifact_sha256': {p.name: digest(p) for p in sorted(build.iterdir())}})
        print('Clean-room ' + args.mode + ' acceptance: PASS', flush=True)
    except BaseException as error:
        mark_failure(statuses, active_phase)
        write_json(evidence / 'FAILED.json', {'status': 'FAIL', 'error': repr(error), 'completed_status': statuses})
        write_json(evidence / 'status.json', statuses)
        raise


if __name__ == '__main__':
    main()
