#!/usr/bin/env python3
"""autopush: watch a directory and auto-commit & push changes to git.

lightweight polling watcher (no external deps). intended for linux/local use.

usage: set up ssh or credential helper for pushing, then run:
  python3 s/tools/autopush.py --path /home/shuwen/s --debounce 2

environment variables:
  git_remote: git remote name (default: origin)
  git_branch: branch to push (default: current branch)
  git_author_name / git_author_email: optional commit author
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


def current_branch()  str:
    p = subprocess.run(["git", "rev-parse", "--abbrev-ref", "head"], capture_output=true, text=true)
    if p.returncode != 0:
        return "main"
    return p.stdout.strip()


def scan_mtimes(root: path)  dict:
    mt = {}
    for p in root.rglob("*"):
        try:
            if p.is_file():
                mt[str(p)] = p.stat().st_mtime
        except exception:
            continue
    return mt


def git_has_staged_changes()  bool:
    p = subprocess.run(["git", "diff", "--cached", "--quiet", "--exit-code"])
    return p.returncode != 0


def run_git_commit_and_push(remote: str, branch: str, commit_msg: str, author_name: str | none, author_email: str | none)  none:
    env = os.environ.copy()
    if author_name:
        env["git_author_name"] = author_name
    if author_email:
        env["git_author_email"] = author_email

    # git add all
    subprocess.run(["git", "add", "-a"])

    if not git_has_staged_changes():
        print("no changes to commit.")
        return

    commit_cmd = ["git", "commit", "-m", commit_msg]
    print("committing: ", " ".join(commit_cmd))
    p = subprocess.run(commit_cmd, env=env)
    if p.returncode != 0:
        print("git commit failed", file=sys.stderr)
        return

    push_cmd = ["git", "push", remote, branch]
    print("pushing: ", " ".join(push_cmd))
    p2 = subprocess.run(push_cmd)
    if p2.returncode != 0:
        print("git push failed", file=sys.stderr)


def main()  none:
    parser = argparse.argumentparser()
    parser.add_argument("--path", default=".", help="path to watch (git repo root)")
    parser.add_argument("--debounce", type=float, default=2.0, help="debounce seconds to coalesce changes")
    parser.add_argument("--remote", default=os.environ.get("git_remote", "origin"), help="git remote name")
    parser.add_argument("--branch", default=os.environ.get("git_branch"), help="git branch (defaults to current)")
    args = parser.parse_args()

    root = path(args.path).resolve()
    if not (root / ".git").exists():
        print(f"error: {root} is not a git repository", file=sys.stderr)
        sys.exit(1)

    os.chdir(root)

    branch = args.branch or current_branch()
    author_name = os.environ.get("git_author_name")
    author_email = os.environ.get("git_author_email")
    remote = args.remote

    print(f"watching {root}  (push -> {remote}/{branch})")

    last_scan = scan_mtimes(root)
    pending = false
    last_event_time = 0.0

    try:
        while true:
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
                pending = true
                last_event_time = now
                print(f"detected {len(changed)} change(s). debouncing for {args.debounce}s.")

            if pending and (now - last_event_time) >= args.debounce:
                # perform commit+push
                files_short = ", ".join(path(p).name for p in changed[:8])
                if len(changed) > 8:
                    files_short += ", ..."
                msg = f"auto-update: {files_short}"
                run_git_commit_and_push(remote, branch, msg, author_name, author_email)
                pending = false
                # refresh base scan
                last_scan = scan_mtimes(root)

    except keyboardinterrupt:
        print("stopped by user")


if __name__ == "__main__":
    main()
