#!/usr/bin/env bash
#
# s-bootstrap-safe.sh — run the S compiler bootstrap without freezing VS Code.
#
# Why this exists
# ---------------
# The bootstrap "stage1" process grows to ~30 GiB on a 31 GiB machine. When it is
# launched from the VS Code integrated terminal it lives inside VS Code's own
# cgroup scope (…/app-com.microsoft.VSCode-*.scope), so when memory is exhausted
# the kernel / systemd-oomd kills processes in that scope and the editor freezes.
#
# This wrapper fixes that by:
#   1. Running the whole bootstrap tree in its OWN memory-capped systemd scope.
#      The cgroup v2 OOM killer then targets only this scope — never VS Code or
#      the desktop — so the editor stays responsive even if the bootstrap dies.
#   2. Enforcing a single running bootstrap at a time (flock), which stops the
#      repeated/overlapping runs that were hammering memory all day.
#   3. Optionally detaching into tmux (--tmux) so the job survives closing the
#      VS Code window.
#
# It does NOT make a ~30 GiB bootstrap succeed on a 31 GiB box — that needs the
# stage1 memory blow-up fixed and/or more swap. It makes the failure safe and
# contained instead of taking the editor down with it.
#
# Usage
# -----
#   script/s-bootstrap-safe.sh [--tmux] [make-target]
#
#   script/s-bootstrap-safe.sh                      # capped, foreground
#   script/s-bootstrap-safe.sh --tmux               # capped, detached in tmux
#   script/s-bootstrap-safe.sh hosted-bootstrap     # a different target
#
# Tunables (environment)
# ----------------------
#   S_BOOTSTRAP_MEM_MAX   hard RAM cap for the scope           (default 20G)
#   S_BOOTSTRAP_MEM_HIGH  throttle threshold before the cap    (default 18G)
#   S_BOOTSTRAP_SWAP_MAX  swap cap for the scope               (default 6G)
#   S_BOOTSTRAP_TARGET    default make target                  (native-bootstrap-imports)
#
set -euo pipefail

MEM_MAX=${S_BOOTSTRAP_MEM_MAX:-20G}
MEM_HIGH=${S_BOOTSTRAP_MEM_HIGH:-18G}
SWAP_MAX=${S_BOOTSTRAP_SWAP_MAX:-6G}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$script_dir/.." && pwd)

use_tmux=0
target=${S_BOOTSTRAP_TARGET:-native-bootstrap-imports}
for arg in "$@"; do
    case "$arg" in
        --tmux) use_tmux=1 ;;
        -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
        -*) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
        *)  target=$arg ;;
    esac
done

log_dir="$root/.bootstrap"
mkdir -p "$log_dir"
log_file="$log_dir/bootstrap-$(date +%Y%m%d-%H%M%S).log"
lock_file="$log_dir/.bootstrap.lock"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have systemd-run; then
    printf 'error: systemd-run not found; cannot create an isolated memory cap.\n' >&2
    printf 'Run the bootstrap under "ulimit -v" or in a separate login session instead.\n' >&2
    exit 1
fi

# --- optional: detach into tmux so the job outlives the VS Code window ---------
if [ "$use_tmux" = 1 ]; then
    if ! have tmux; then
        printf 'error: --tmux requested but tmux is not installed (apt install tmux).\n' >&2
        exit 1
    fi
    session="s-bootstrap"
    if tmux has-session -t "$session" 2>/dev/null; then
        printf 'A tmux session "%s" already exists. Attach with: tmux attach -t %s\n' "$session" "$session" >&2
        exit 1
    fi
    tmux new-session -d -s "$session" \
        "S_BOOTSTRAP_MEM_MAX='$MEM_MAX' S_BOOTSTRAP_MEM_HIGH='$MEM_HIGH' S_BOOTSTRAP_SWAP_MAX='$SWAP_MAX' '$script_dir/$(basename "${BASH_SOURCE[0]}")' '$target'"
    printf 'Bootstrap started detached in tmux session "%s".\n' "$session"
    printf '  Attach:  tmux attach -t %s\n' "$session"
    printf '  Detach:  Ctrl-b then d\n'
    exit 0
fi

# --- single-instance guard: never let two bootstraps compete for memory --------
exec 9>"$lock_file"
if ! flock -n 9; then
    printf 'error: another bootstrap is already running (lock: %s).\n' "$lock_file" >&2
    printf 'Running two at once overwrites the same output and exhausts memory — refusing.\n' >&2
    exit 1
fi

scope_name="s-bootstrap-$$"

printf '=== S bootstrap (isolated + memory-capped) ===\n'
printf 'Target   : %s\n' "$target"
printf 'Mem cap  : max=%s high=%s swap=%s\n' "$MEM_MAX" "$MEM_HIGH" "$SWAP_MAX"
printf 'Scope    : %s (own cgroup — OOM here cannot freeze VS Code)\n' "$scope_name"
printf 'Log      : %s\n\n' "$log_file"

set +e
systemd-run --user --scope \
    --unit "$scope_name" \
    -p MemoryMax="$MEM_MAX" \
    -p MemoryHigh="$MEM_HIGH" \
    -p MemorySwapMax="$SWAP_MAX" \
    --quiet \
    bash -c '
        # Make this tree the preferred OOM victim if a global shortage ever hits,
        # so the system kills the bootstrap before anything else.
        echo 1000 > /proc/self/oom_score_adj 2>/dev/null || true
        set -o pipefail
        exec make -C "'"$root"'" "'"$target"'"
    ' 2>&1 | tee "$log_file"
status=${PIPESTATUS[0]}
set -e

printf '\n'
if [ "$status" -eq 0 ]; then
    printf '✓ Bootstrap finished (log: %s)\n' "$log_file"
else
    printf '✗ Bootstrap exited with status %s (log: %s)\n' "$status" "$log_file"
    if grep -qiE 'killed|out of memory|signal 9' "$log_file" 2>/dev/null; then
        printf '  Likely the scope hit its %s memory cap and was OOM-killed.\n' "$MEM_MAX"
        printf '  VS Code was protected — the kill was confined to this scope.\n'
        printf '  To let it use more, raise S_BOOTSTRAP_MEM_MAX, add swap, or fix stage1 memory use.\n'
    fi
fi
exit "$status"
