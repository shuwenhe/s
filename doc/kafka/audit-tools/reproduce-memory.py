"""Copy the retained diagnostic harness into a fresh repo-local evidence directory."""
from pathlib import Path
import shutil,subprocess,sys,shlex
root=Path('/root/shuwen/s').resolve()
source=Path(__file__).resolve().parent
target=Path(sys.argv[1]);target=(root/target).resolve() if not target.is_absolute() else target.resolve()
if not target.is_relative_to(root):raise SystemExit('output must stay under repository')
target.mkdir(parents=True,exist_ok=False)
for name in ['memory.s','measure.py','AuditProducer.java']:shutil.copyfile(source/name,target/name)
s=(source/'memory-run.sh').read_text().replace('run="$PWD/.bootstrap/kafka-audit/audit-20261115"','run='+shlex.quote(str(target)))
(target/'memory-run.sh').write_text(s)
raise SystemExit(subprocess.run(['bash',str(target/'memory-run.sh')],cwd=root).returncode)
