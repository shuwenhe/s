"""Generator checks must reject stale output without modifying it."""
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).with_name('extensions_generate.py')
with tempfile.TemporaryDirectory() as temporary:
    output = Path(temporary) / 'runtime.s'
    subprocess.run(['python3', str(script), '--output', str(output)], check=True)
    expected = output.read_bytes()
    subprocess.run(['python3', str(script), '--check', '--output', str(output)], check=True)
    assert output.read_bytes() == expected
    stale = expected + b'// intentionally stale\n'
    output.write_bytes(stale)
    result = subprocess.run(['python3', str(script), '--check', '--output', str(output)], capture_output=True, text=True)
    assert result.returncode != 0 and 'stale generated' in result.stderr, result
    assert output.read_bytes() == stale, '--check modified stale source'
    output.unlink()
    result = subprocess.run(['python3', str(script), '--check', '--output', str(output)], capture_output=True, text=True)
    assert result.returncode != 0 and 'stale generated' in result.stderr, result
    assert not output.exists(), '--check created missing source'
print('native extension generator fresh/stale/missing nonmutation checks passed')
