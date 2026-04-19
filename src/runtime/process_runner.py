from __future__ import annotations

import os

from runtime.compat import *


default_executable_path = path(__file__).with_name("process_runner")


def get_executable() -> path:
    return path(os.environ.get("s_process_runner_executable", default_executable_path))
