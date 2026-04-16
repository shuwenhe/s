#!/usr/bin/env python3

import argparse
import fcntl
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(
        description="Watch a git repository and auto commit/push stable changes."
    )
    parser.add_argument("--repo", default=".", help="Path to the git repository.")
    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="Polling interval in seconds.",
    )
    parser.add_argument(
        "--debounce",
        type=float,
        default=5.0,
        help="Wait time after the last change before committing.",
    )
    parser.add_argument(
        "--message-prefix",
        default="chore: auto update",
        help="Prefix used for generated commit messages.",
    )
    return parser.parse_args()


def git(repo, *args, check=True):
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
    )
    if check and result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "git command failed")
    return result


def acquire_lock(lock_path):
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    lock_file = open(lock_path, "w", encoding="utf-8")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        raise RuntimeError("auto commit watcher is already running") from exc
    lock_file.write(str(os.getpid()))
    lock_file.flush()
    return lock_file


def get_status(repo):
    return git(repo, "status", "--porcelain", check=True).stdout.strip()


def current_branch(repo):
    return git(repo, "branch", "--show-current", check=True).stdout.strip()


def has_upstream(repo):
    result = git(
        repo,
        "rev-parse",
        "--abbrev-ref",
        "--symbolic-full-name",
        "@{u}",
        check=False,
    )
    return result.returncode == 0


def summarize_paths(paths):
    labels = []
    mapping = [
        ("src/cmd/compile/internal/compiler/", "compiler"),
        ("src/s/", "language packages"),
        ("src/runtime/", "runtime"),
        ("src/prelude/", "standard library"),
        ("src/result/", "standard library"),
        ("src/option/", "standard library"),
        ("src/vec/", "standard library"),
        ("src/io/", "standard library"),
        ("src/fs/", "standard library"),
        ("src/env/", "standard library"),
        ("src/process/", "standard library"),
        ("src/cmd/", "commands"),
        ("doc/", "docs"),
        ("misc/editor/vscode/", "VS Code support"),
        (".vscode/", "workspace settings"),
        ("misc/scripts/", "tooling"),
        ("misc/examples/", "examples"),
    ]
    for prefix, label in mapping:
        if any(path.startswith(prefix) for path in paths):
            labels.append(label)
    if not labels:
        labels.append("project files")
    return labels


def build_commit_message(paths):
    labels = summarize_paths(paths)
    if len(labels) == 1:
        return f"Update {labels[0]}."
    if len(labels) == 2:
        return f"Update {labels[0]} and {labels[1]}."
    return f"Update {', '.join(labels[:-1])}, and {labels[-1]}."


def commit_and_push(repo, message_prefix):
    git(repo, "add", "-A", check=True)
    cached = git(repo, "diff", "--cached", "--name-only", check=True).stdout.strip()
    if not cached:
        return False
    changed_paths = [line.strip() for line in cached.splitlines() if line.strip()]

    message = f"{message_prefix}: {build_commit_message(changed_paths)}"
    git(repo, "commit", "-m", message, check=True)

    branch = current_branch(repo)
    if not branch:
        raise RuntimeError("cannot determine current branch")

    if has_upstream(repo):
        git(repo, "push", check=True)
    else:
        git(repo, "push", "-u", "origin", branch, check=True)
    return True


def main():
    args = parse_args()
    repo = Path(args.repo).resolve()
    git_dir = repo / ".git"
    lock_path = git_dir / "auto_commit_push.lock"

    if not git_dir.exists():
        print(f"{repo} is not a git repository", file=sys.stderr)
        return 1

    try:
        lock_file = acquire_lock(lock_path)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    running = True

    def stop_handler(signum, frame):
        del signum, frame
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop_handler)
    signal.signal(signal.SIGTERM, stop_handler)

    print(f"watching {repo}")
    print(f"interval={args.interval}s debounce={args.debounce}s")
    sys.stdout.flush()

    last_seen_status = None
    dirty_since = None
    last_processed_status = None

    try:
        while running:
            try:
                status = get_status(repo)
            except Exception as exc:
                print(f"[error] status failed: {exc}", file=sys.stderr)
                sys.stderr.flush()
                time.sleep(max(args.interval, 3.0))
                continue

            if not status:
                last_seen_status = None
                dirty_since = None
                time.sleep(args.interval)
                continue

            if status != last_seen_status:
                last_seen_status = status
                dirty_since = time.time()
                print("[change detected]")
                print(status)
                sys.stdout.flush()
                time.sleep(args.interval)
                continue

            if dirty_since is None or (time.time() - dirty_since) < args.debounce:
                time.sleep(args.interval)
                continue

            if status == last_processed_status:
                time.sleep(args.interval)
                continue

            try:
                committed = commit_and_push(repo, args.message_prefix)
            except Exception as exc:
                print(f"[error] commit/push failed: {exc}", file=sys.stderr)
                sys.stderr.flush()
                last_processed_status = None
                time.sleep(max(args.interval, 5.0))
                continue

            if committed:
                print("[pushed] changes committed and pushed")
                sys.stdout.flush()
                last_processed_status = status
                last_seen_status = None
                dirty_since = None
            time.sleep(args.interval)
    finally:
        lock_file.close()
        try:
            lock_path.unlink(missing_ok=True)
        except OSError:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
