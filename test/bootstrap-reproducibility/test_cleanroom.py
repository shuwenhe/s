"""Behavioral guards for the clean-room bootstrap; no compiler mocks."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'misc/scripts/cleanroom-selfhost.py'

def load():
    spec = importlib.util.spec_from_file_location('cleanroom', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class CleanroomTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.m = load()

    def repository(self):
        root = self.base / 'repo'; root.mkdir()
        subprocess.run(['git', 'init', '-q', root], check=True)
        (root / '.gitignore').write_text('bin/\n.bootstrap/\n')
        (root / 'source.s').write_text('package main\nfunc main() int { return 42 }\n')
        subprocess.run(['git', '-C', root, 'add', '.'], check=True)
        subprocess.run(['git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'source'], check=True)
        return root

    def test_new_checkout_excludes_ignored_binaries_and_uses_distinct_inodes(self):
        repo = self.repository(); (repo/'bin').mkdir(); (repo/'bin/stage1').write_bytes(b'old')
        clone = self.base/'clone'
        revision = self.m.create_checkout(repo, 'HEAD', clone)
        self.assertFalse((clone/'bin').exists())
        self.assertNotEqual((clone/'source.s').stat().st_ino, (repo/'source.s').stat().st_ino)
        snapshot = self.m.source_manifest(clone)
        (repo/'source.s').write_text('changed parent\n')
        self.m.verify_sources(clone, revision, snapshot)
        (clone/'source.s').write_text('changed frozen source\n')
        with self.assertRaisesRegex(RuntimeError, 'source|worktree'):
            self.m.verify_sources(clone, revision, snapshot)

    def test_checkout_ignores_inherited_git_configuration_and_matches_blob(self):
        from unittest.mock import patch
        repo=self.repository()
        (repo/'script.sh').write_bytes(b'#!/bin/sh\necho committed\n')
        subprocess.run(['git','-C',repo,'add','script.sh'],check=True)
        subprocess.run(['git','-C',repo,'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','script'],check=True)
        with patch.dict(os.environ,{'GIT_CONFIG_COUNT':'1','GIT_CONFIG_KEY_0':'core.autocrlf','GIT_CONFIG_VALUE_0':'true'}):
            clone=self.base/'clone';revision=self.m.create_checkout(repo,'HEAD',clone)
            self.assertEqual((clone/'script.sh').read_bytes(),b'#!/bin/sh\necho committed\n')
            self.m.verify_committed_blobs(clone,revision)
        (clone/'script.sh').write_bytes(b'changed\n')
        with self.assertRaisesRegex(RuntimeError,'blob|committed'):
            self.m.verify_committed_blobs(clone,revision)

    def test_failure_marks_active_phase_and_keeps_later_phases_not_run(self):
        statuses={'source':'PASS','seed':'PASS','stage1':'PASS','stage2':'NOT RUN','stage3':'NOT RUN'}
        self.m.mark_failure(statuses,'stage2')
        self.assertEqual(statuses['stage2'],'FAIL')
        self.assertEqual(statuses['stage3'],'NOT RUN')

    def test_dirty_repository_is_rejected_before_clone(self):
        repo = self.repository(); (repo/'source.s').write_text('dirty')
        with self.assertRaisesRegex(RuntimeError, 'dirty|clean'):
            self.m.create_checkout(repo, 'HEAD', self.base/'clone')
        self.assertFalse((self.base/'clone').exists())

    def test_existing_output_directory_is_never_reused(self):
        output=self.base/'out';output.mkdir();sentinel=output/'stage1';sentinel.write_text('keep')
        with self.assertRaises((FileExistsError, RuntimeError)):
            self.m.fresh_directory(output)
        self.assertEqual(sentinel.read_text(), 'keep')

    def test_environment_removes_bootstrap_and_compiler_overrides(self):
        env=self.m.clean_environment(self.base/'root',self.base/'tmp',{'PATH':'/old/bin','S_BOOTSTRAP_RUNNER':'old-stage1','S_SOURCE_ROOT':'old','S_CLOSURE_MODE':'test','LD_PRELOAD':'old.so','CC':'old-cc','CFLAGS':'bad','MAKEFLAGS':'-n','HOME':'/home/example'})
        for key in ['S_BOOTSTRAP_RUNNER','S_CLOSURE_MODE','LD_PRELOAD','CC','CFLAGS','MAKEFLAGS']:
            self.assertNotIn(key,env)
        self.assertEqual(env['PATH'],'/usr/bin:/bin')
        self.assertEqual(env['S_SOURCE_ROOT'],str(self.base/'root'))

    def test_failed_command_preserves_separate_logs_metrics_and_output(self):
        logs=self.base/'logs';logs.mkdir()
        runner=self.m.CommandRunner(self.base,logs,self.m.clean_environment(self.base,self.base/'tmp'))
        cmd=[sys.executable,'-c','import sys; print("stdout-proof"); print("stderr-proof",file=sys.stderr); open("partial","w").write("partial"); sys.exit(7)']
        with self.assertRaisesRegex(RuntimeError,'7'):
            runner.run('broken',cmd)
        import json
        receipt=json.loads((logs/'broken.json').read_text())
        self.assertEqual(receipt['exit'],7)
        self.assertGreaterEqual(receipt['peak_rss_kb'],0)
        self.assertIn('stdout-proof',(logs/'broken.stdout.log').read_text())
        self.assertIn('stderr-proof',(logs/'broken.stderr.log').read_text())
        self.assertEqual((self.base/'partial').read_text(),'partial')
        with self.assertRaises((FileExistsError,RuntimeError)):
            runner.run('broken',cmd)

    def test_trace_keeps_full_long_executable_paths(self):
        import shutil
        directory=self.base/('long-path-'*10);directory.mkdir()
        executable=directory/'compiler';shutil.copy2('/usr/bin/true',executable)
        logs=self.base/'logs';logs.mkdir()
        runner=self.m.CommandRunner(self.base,logs,self.m.clean_environment(self.base,self.base/'tmp'))
        runner.run('long-executable',[executable],trace=True)

    def test_trace_rejects_delegation_to_another_compiler_or_program(self):
        logs=self.base/'logs';logs.mkdir()
        runner=self.m.CommandRunner(self.base,logs,self.m.clean_environment(self.base,self.base/'tmp'))
        with self.assertRaisesRegex(RuntimeError,'unexpected executable'):
            runner.run('delegated',[sys.executable,'-c','import os; os.execv("/usr/bin/true",["true"])'],trace=True)

    def test_success_missing_output_is_not_pass(self):
        logs=self.base/'logs';logs.mkdir()
        runner=self.m.CommandRunner(self.base,logs,self.m.clean_environment(self.base,self.base/'tmp'))
        with self.assertRaisesRegex(RuntimeError,'missing|output'):
            runner.run('missing',[sys.executable,'-c','pass'],[self.base/'absent'])
        import json
        self.assertEqual(json.loads((logs/'missing.json').read_text())['status'],'FAIL')

    def test_byte_comparison_rejects_changes_without_normalization(self):
        a=self.base/'a';b=self.base/'b';a.write_bytes(b'bytes\n');b.write_bytes(b'bytes\r\n')
        with self.assertRaisesRegex(RuntimeError,'differ|converg'):
            self.m.compare_artifacts(a,b)
        b.write_bytes(a.read_bytes());self.assertEqual(self.m.compare_artifacts(a,b),self.m.digest(a))

    def oracle_mir(self):
        return """mir-program-v1 package=app entry=app.main
function app.dead external=false
results int
function app.__global_init_value external=false
results int
instruction call results=0 types=int operands= integer=0 symbol=app.helper
function app.main external=false
results int
instruction call results=0 types=int operands= integer=0 symbol=app.loop
function app.helper external=false
results int
function app.loop external=false
results int
instruction call results=0 types=int operands= integer=0 symbol=app.loop
call app.__global_init_value -> app.helper block=0 instruction=0
call app.main -> app.loop block=0 instruction=0
call app.loop -> app.loop block=0 instruction=0
"""

    def oracle_assembly(self):
        return """# S-NATIVE-AMD64-V1
_start:
 call s_native_initialize_globals
 call s_native_entry
s_native_entry:
 jmp s_native_fn_1
s_native_fn_0:
 call s_native_fn_2
 ret
.size s_native_fn_0, .-s_native_fn_0
s_native_fn_1:
 call s_native_fn_3
 ret
.size s_native_fn_1, .-s_native_fn_1
s_native_fn_2:
 ret
.size s_native_fn_2, .-s_native_fn_2
s_native_fn_3:
 call s_native_fn_3
 ret
.size s_native_fn_3, .-s_native_fn_3
s_native_initialize_globals:
 call s_native_fn_0
 ret
.size s_native_initialize_globals, .-s_native_initialize_globals
"""

    def test_mir_oracle_independently_keeps_initializer_roots_and_recursion(self):
        expected=self.m.expected_functions(self.oracle_mir())
        self.assertEqual(expected['functions'],['app.__global_init_value','app.main','app.helper','app.loop'])
        self.m.verify_expected_functions(self.oracle_assembly(),expected)
        # Both compilers could produce this same omission; equality alone is insufficient.
        omitted=self.oracle_assembly().replace(' call s_native_fn_2\n','').replace('s_native_fn_2:\n ret\n.size s_native_fn_2, .-s_native_fn_2\n','')
        for assembly in [omitted,omitted]:
            with self.assertRaisesRegex(RuntimeError,'expected|inventory'):
                self.m.verify_expected_functions(assembly,expected)
        missing_call=self.oracle_assembly().replace(' call s_native_fn_3\n','',1)
        with self.assertRaisesRegex(RuntimeError,'call|edge'):
            self.m.verify_expected_functions(missing_call,expected)

    def test_mir_oracle_rejects_duplicate_missing_and_inconsistent_symbols(self):
        for broken in [self.oracle_mir()+'function app.main external=false\nresults int\n',
                       self.oracle_mir().replace('entry=app.main','entry=absent'),
                       self.oracle_mir().replace('symbol=app.helper','symbol=missing'),
                       self.oracle_mir().replace('call app.main -> app.loop block=0 instruction=0\n','')]:
            with self.assertRaises(RuntimeError): self.m.expected_functions(broken)

    def test_reachable_function_audit_rejects_undefined_and_duplicate_labels(self):
        assembly='# S-NATIVE-AMD64-V1\n_start:\n call s_native_entry\ns_native_entry:\n jmp s_native_fn_0\ns_native_fn_0:\n ret\n'
        self.assertEqual(self.m.function_labels(assembly),['s_native_fn_0'])
        with self.assertRaisesRegex(RuntimeError,'undefined|missing'):
            self.m.function_labels(assembly+' call s_native_fn_1\n')
        with self.assertRaisesRegex(RuntimeError,'duplicate'):
            self.m.function_labels(assembly+'s_native_fn_0:\n ret\n')
        with self.assertRaisesRegex(RuntimeError,'entry|start'):
            self.m.function_labels(assembly.replace('_start:','other:'))

if __name__=='__main__': unittest.main()
