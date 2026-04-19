from __future__ import annotations

import os

from runtime.compat import *


default_executable_path = path(__file__).with_name("launcher")
default_library_path = path(__file__).with_name("liblauncher.so")


def get_executable() -> path:
    return path(os.environ.get("s_launcher_executable", default_executable_path))


def get_library_path() -> path:
    return path(os.environ.get("s_launcher_library", default_library_path))
