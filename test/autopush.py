#!/usr/bin/env python3
"""Autopush: watch a directory and auto-commit & push changes to Git.

Lightweight polling watcher (no external deps). Intended for Linux/local use.

Usage: set up SSH or credential helper for pushing, then run:
  python3 s/tools/autopush.py --path /home/shuwen/s --debounce 2

Environment variables:
  GIT_REMOTE: git remote name (default: origin)
  GIT_BRANCH: branch to push (default: current branch)
  GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL: optional commit author
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


def current_branch()  str:
    p = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True)
    if p.returncode != 0:
        return "main"
    return p.stdout.strip()


def scan_mtimes(root: Path)  dict:
    mt = {}
    for p in root.rglob("*"):
        try:
            if p.is_file():
                mt[str(p)] = p.stat().st_mtime
        except Exception:
            continue
    return mt


def git_has_staged_changes()  bool:
    p = subprocess.run(["git", "diff", "--cached", "--quiet", "--exit-code"])
    return p.returncode != 0


def run_git_commit_and_push(remote: str, branch: str, commit_msg: str, author_name: str | None, author_email: str | None)  None:
    env = os.environ.copy()
    if author_name:
        env["GIT_AUTHOR_NAME"] = author_name
    if author_email:
        env["GIT_AUTHOR_EMAIL"] = author_email

    # git add all
    subprocess.run(["git", "add", "-A"])

    if not git_has_staged_changes():
        print("No changes to commit.")
        return

    commit_cmd = ["git", "commit", "-m", commit_msg]
    print("Committing: ", " ".join(commit_cmd))
    p = subprocess.run(commit_cmd, env=env)
    if p.returncode != 0:
        print("git commit failed", file=sys.stderr)
        return

    push_cmd = ["git", "push", remote, branch]
    print("Pushing: ", " ".join(push_cmd))
    p2 = subprocess.run(push_cmd)
    if p2.returncode != 0:
        print("git push failed", file=sys.stderr)


def main()  None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", default=".", help="Path to watch (git repo root)")
    parser.add_argument("--debounce", type=float, default=2.0, help="Debounce seconds to coalesce changes")
    parser.add_argument("--remote", default=os.environ.get("GIT_REMOTE", "origin"), help="Git remote name")
    parser.add_argument("--branch", default=os.environ.get("GIT_BRANCH"), help="Git branch (defaults to current)")
    args = parser.parse_args()

    root = Path(args.path).resolve()
    if not (root / ".git").exists():
        print(f"Error: {root} is not a git repository", file=sys.stderr)
        sys.exit(1)

    os.chdir(root)

    branch = args.branch or current_branch()
    author_name = os.environ.get("GIT_AUTHOR_NAME")
    author_email = os.environ.get("GIT_AUTHOR_EMAIL")
    remote = args.remote

    print(f"Watching {root}  (push -> {remote}/{branch})")

    last_scan = scan_mtimes(root)
    pending = False
    last_event_time = 0.0

    try:
        while True:
            time.sleep(max(0.1, args.debounce / 2))
            now = time.time()
            mt = scan_mtimes(root)
            changed = []
            # detect new or modified files
            for p, t in mt.items():
                if p not in last_scan or last_scan[p] != t:
                    changed.append(p)

            # detect removed files
            for p in list(last_scan.keys()):
                if p not in mt:
                    changed.append(p)

            if changed:
                pending = True
                last_event_time = now
                print(f"Detected {len(changed)} change(s). Debouncing for {args.debounce}s.")

            if pending and (now - last_event_time) >= args.debounce:
                # perform commit+push
                files_short = ", ".join(Path(p).name for p in changed[:8])
                if len(changed) > 8:
                    files_short += ", ..."
                msg = f"Auto-update: {files_short}"
                run_git_commit_and_push(remote, branch, msg, author_name, author_email)
                pending = False
                # refresh base scan
                last_scan = scan_mtimes(root)

    except KeyboardInterrupt:
        print("Stopped by user")


if __name__ == "__main__":
    main()
