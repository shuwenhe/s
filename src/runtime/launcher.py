from __future__ import annotations

import subprocess

from runtime.process_runner import get_executable


def run_process_runner(argv: list[str]) -> int:
    executable = str(get_executable())
    completed = subprocess.run([executable, *argv], capture_output=True, text=True)
    return int(completed.returncode)

