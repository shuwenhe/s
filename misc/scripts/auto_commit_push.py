#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Watch a git repository and auto commit/push stable changes.")
    parser.add_argument("--repo", default=".", help="Path to the git repository.")
    parser.add_argument("--interval", type=float, default=2.0, help="Polling interval in seconds.")
    parser.add_argument("--debounce", type=float, default=3.0, help="Wait after the last change before committing.")
    parser.add_argument("--branch", default=os.environ.get("NEURX_AUTO_PUSH_BRANCH", "main"), help="Branch to keep current and push.")
    parser.add_argument("--remote", default=os.environ.get("NEURX_AUTO_PUSH_REMOTE", "origin"), help="Git remote to push to.")
    parser.add_argument("--message-prefix", default=os.environ.get("NEURX_AUTO_PUSH_MESSAGE_PREFIX", "chore: auto save"), help="Commit message prefix.")
    return parser.parse_args()


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(["git", "-C", str(repo), *args], text=True, capture_output=True)
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git command failed")
    return result


def acquire_lock(lock_path: Path):
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_file = open(lock_path, "w", encoding="utf-8")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        raise RuntimeError("auto commit watcher is already running") from exc
    lock_file.write(str(os.getpid()))
    lock_file.flush()
    return lock_file


def current_branch(repo: Path) -> str:
    return git(repo, "branch", "--show-current", check=True).stdout.strip()


def has_remote(repo: Path, remote: str) -> bool:
    result = git(repo, "remote", "get-url", remote, check=False)
    return result.returncode == 0


def list_changed_paths(repo: Path) -> list[str]:
    result = git(repo, "diff", "--cached", "--name-only", check=True)
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def summarize_paths(paths: list[str]) -> str:
    if not paths:
        return "update"
    if any(path.startswith("src/") for path in paths):
        return "update source"
    if any(path.startswith("misc/") for path in paths):
        return "update tooling"
    if any(path.startswith("doc/") or path.endswith(".md") for path in paths):
        return "update docs"
    return "update files"


def commit_and_push(repo: Path, remote: str, branch: str, message_prefix: str) -> bool:
    git(repo, "add", "-A", check=True)
    if git(repo, "diff", "--cached", "--quiet", check=False).returncode == 0:
        return False

    changed_paths = list_changed_paths(repo)
    message = f"{message_prefix}: {summarize_paths(changed_paths)}"
    env = os.environ.copy()
    env["NEURX_SKIP_AUTO_PUSH"] = "1"

    commit = subprocess.run(
        ["git", "-C", str(repo), "commit", "-m", message],
        text=True,
        capture_output=True,
        env=env,
    )
    if commit.returncode != 0:
        raise RuntimeError(commit.stderr.strip() or "git commit failed")

    if not has_remote(repo, remote):
        raise RuntimeError(f"remote '{remote}' is not configured")

    push = subprocess.run(["git", "-C", str(repo), "push", remote, branch], text=True, capture_output=True)
    if push.returncode != 0:
        raise RuntimeError(push.stderr.strip() or "git push failed")

    return True


def scan_mtimes(root: Path) -> dict[str, float]:
    mtimes: dict[str, float] = {}
    for path in root.rglob("*"):
        if ".git" in path.parts:
            continue
        try:
            if path.is_file():
                mtimes[str(path)] = path.stat().st_mtime
        except OSError:
            continue
    return mtimes


def main() -> int:
    args = parse_args()
    repo = Path(args.repo).resolve()
    if not (repo / ".git").exists():
        print(f"{repo} is not a git repository", file=sys.stderr)
        return 1

    branch = args.branch
    if current_branch(repo) != branch:
        print(f"watcher: current branch must be '{branch}'", file=sys.stderr)
        return 1

    lock_path = repo / ".git" / "auto_commit_push.lock"
    acquire_lock(lock_path)

    running = True

    def stop_handler(signum, frame):
        del signum, frame
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop_handler)
    signal.signal(signal.SIGTERM, stop_handler)

    print(f"watching {repo}")
    print(f"branch={branch} remote={args.remote} interval={args.interval}s debounce={args.debounce}s")
    sys.stdout.flush()

    last_scan = scan_mtimes(repo)
    dirty_since = None
    last_signature = None

    try:
        while running:
            current = scan_mtimes(repo)
            changed = [path for path, mtime in current.items() if last_scan.get(path) != mtime]
            removed = [path for path in last_scan if path not in current]

            if changed or removed:
                dirty_since = time.time()
                signature = tuple(sorted(changed + removed))
                if signature != last_signature:
                    print(f"[change] {len(changed) + len(removed)} file(s)")
                    sys.stdout.flush()
                    last_signature = signature
                time.sleep(args.interval)
                last_scan = current
                continue

            if dirty_since is not None and (time.time() - dirty_since) >= args.debounce:
                try:
                    committed = commit_and_push(repo, args.remote, branch, args.message_prefix)
                except Exception as exc:
                    print(f"[error] commit/push failed: {exc}", file=sys.stderr)
                    sys.stderr.flush()
                    dirty_since = None
                    last_signature = None
                    time.sleep(max(args.interval, 3.0))
                    continue

                if committed:
                    print("[pushed] changes committed and pushed")
                    sys.stdout.flush()
                dirty_since = None
                last_signature = None
                last_scan = scan_mtimes(repo)

            time.sleep(args.interval)
    finally:
        try:
            lock_path.unlink(missing_ok=True)
        except OSError:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
