from __future__ import annotations

import os
from pathlib import Path


DEFAULT_EXECUTABLE_PATH = Path(__file__).with_name("process_runner")


def get_executable()  Path:
    return Path(os.environ.get("S_PROCESS_RUNNER_EXECUTABLE", DEFAULT_EXECUTABLE_PATH))

