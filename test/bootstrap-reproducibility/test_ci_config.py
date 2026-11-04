"""CI must exercise fresh builds and retain evidence even when a command fails."""
from pathlib import Path
import re
import os
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]

class CIConfigurationTests(unittest.TestCase):
    def test_workflow_has_both_levels_no_caches_and_always_uploads(self):
        path=ROOT/'.github/workflows/selfhost.yml'
        workflow=yaml.load(path.read_text(),Loader=yaml.BaseLoader)
        for trigger in ['push','pull_request','workflow_dispatch','schedule']:
            self.assertIn(trigger,workflow['on'])
        self.assertEqual(set(workflow['jobs']),{'core','full'})
        self.assertEqual(workflow['permissions'],{'contents':'read'})
        for name,job in workflow['jobs'].items():
            self.assertEqual(job['runs-on'],'ubuntu-22.04')
            actions=[step['uses'] for step in job['steps'] if 'uses' in step]
            self.assertTrue(all(re.fullmatch(r'actions/(checkout|upload-artifact)@[0-9a-f]{40}',action) for action in actions))
            self.assertFalse(any('cache' in action for action in actions))
            upload=next(step for step in job['steps'] if step.get('uses','').startswith('actions/upload-artifact@'))
            self.assertEqual(upload['if'],'always()')
            self.assertEqual(upload['with']['if-no-files-found'],'error')
            commands='\n'.join(step.get('run','') for step in job['steps'])
            self.assertIn('ci-core.sh',commands)
            self.assertIn('ripgrep',commands)
            self.assertIn(name,commands)
        self.assertIn('schedule',workflow['jobs']['full']['if'])

    def test_evidence_path_uses_runner_context_only_inside_steps(self):
        workflow=yaml.load((ROOT/'.github/workflows/selfhost.yml').read_text(),Loader=yaml.BaseLoader)
        for name,job in workflow['jobs'].items():
            # GitHub rejects runner context in jobs.<job_id>.env before any job starts.
            self.assertNotIn('runner.',str(job.get('env',{})))
            setup=job['steps'][1]
            self.assertIn('GITHUB_ENV',setup.get('run',''))
            with tempfile.TemporaryDirectory(prefix='runner temp ') as directory:
                env_file=Path(directory)/'environment'
                env_file.touch()
                result=subprocess.run(['bash','-eu','-c',setup['run']],capture_output=True,text=True,
                    env=os.environ|{'RUNNER_TEMP':directory,'GITHUB_ENV':str(env_file),
                                   'GITHUB_RUN_ID':'123','GITHUB_RUN_ATTEMPT':'2'})
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(env_file.read_text().strip(),
                    f'CI_EVIDENCE={directory}/s-selfhost-{name}-123-2')

    def test_entrypoint_rejects_existing_output_without_touching_it(self):
        with tempfile.TemporaryDirectory() as directory:
            out=Path(directory)/'already';out.mkdir();kept=out/'stage1';kept.write_text('preserve')
            tools=Path(directory)/'tools';tools.mkdir()
            apt=tools/'apt-get';apt.write_text('#!/bin/sh\nexit 97\n');apt.chmod(0o755)
            result=subprocess.run(['bash',ROOT/'misc/scripts/ci-core.sh','0'*40,out,'core'],capture_output=True,text=True,env=os.environ|{'PATH':str(tools)+':'+os.environ['PATH']})
            self.assertEqual(result.returncode,2,result.stderr)
            self.assertIn('fresh',result.stderr.lower())
            self.assertEqual(kept.read_text(),'preserve')

if __name__=='__main__':unittest.main()
