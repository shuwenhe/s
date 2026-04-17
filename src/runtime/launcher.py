from __future__ import annotations

import os
from pathlib import Path


DEFAULT_EXECUTABLE_PATH = Path(__file__).with_name("launcher")
DEFAULT_LIBRARY_PATH = Path(__file__).with_name("liblauncher.so")


def get_executable()  Path:
    return Path(os.environ.get("S_LAUNCHER_EXECUTABLE", DEFAULT_EXECUTABLE_PATH))


def get_library_path()  Path:
    return Path(os.environ.get("S_LAUNCHER_LIBRARY", DEFAULT_LIBRARY_PATH))
