#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
script="$root/src/cmd/dist/stage2-stage3-memory-diagnostic.sh"
work=$(mktemp -d)

trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/fake-stage2" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = "--emit-asm" ]
input=$2
output=$3
[ -f "$input" ]
printf '%s\n' '.globl _start' '_start:' '  mov $42, %edi' >"$output"
EOF

cat >"$work/fake-as" <<'EOF'
#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift; output=$1 ;;
    esac
    shift || true
done
[ -n "$output" ]
printf '%s\n' object >"$output"
EOF

cat >"$work/fake-ld" <<'EOF'
#!/bin/sh
set -eu
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) shift; output=$1 ;;
    esac
    shift || true
done
[ -n "$output" ]
printf '%s\n' binary >"$output"
chmod +x "$output"
EOF

chmod +x "$work/fake-stage2" "$work/fake-as" "$work/fake-ld"
printf '%s\n' 'package main' >"$work/compiler.s"
printf '%s\n' runtime >"$work/runtime.o"

S_STAGE2_COMPILER="$work/fake-stage2" \
S_BOOTSTRAP_SOURCE="$work/compiler.s" \
S_BOOTSTRAP_AS="$work/fake-as" \
S_BOOTSTRAP_LD="$work/fake-ld" \
S_BOOTSTRAP_RUNTIME_OBJECT="$work/runtime.o" \
S_BOOTSTRAP_LINKER_SCRIPT="$work/linker.ld" \
S_BOOTSTRAP_TIMEOUT=30 \
    "$script" "$work/out"

report="$work/out/stage2-stage3-memory-report.txt"

[ -f "$report" ]
grep -q '^s-stage2-stage3-memory-diagnostic-v1$' "$report"
grep -q '^git-commit=' "$report"
grep -q '^step=stage2-to-stage3$' "$report"
grep -q '^target=linux/amd64$' "$report"
grep -q '^runner=none$' "$report"
grep -q '^phase.compile.stage=\[3/7\] stage2 -> stage3 / compile$' "$report"
grep -q '^phase.compile.status=0$' "$report"
grep -q '^phase.compile.max-rss-kb=[0-9][0-9]*$' "$report"
grep -q '^phase.compile.max-vms-kb=[0-9][0-9]*$' "$report"
grep -q '^phase.assemble.stage=\[3/7\] stage2 -> stage3 / assemble$' "$report"
grep -q '^phase.assemble.status=0$' "$report"
grep -q '^phase.assemble.max-rss-kb=[0-9][0-9]*$' "$report"
grep -q '^phase.assemble.max-vms-kb=[0-9][0-9]*$' "$report"
grep -q '^phase.link.stage=\[3/7\] stage2 -> stage3 / link$' "$report"
grep -q '^phase.link.status=0$' "$report"
grep -q '^phase.link.max-rss-kb=[0-9][0-9]*$' "$report"
grep -q '^phase.link.max-vms-kb=[0-9][0-9]*$' "$report"
grep -q '^artifact.stage3.S=present$' "$report"
grep -q '^artifact.stage3=present$' "$report"
grep -q '^result=PASS_STAGE3_GENERATED$' "$report"

cat >"$work/fake-runner" <<'EOF'
#!/bin/sh
set -eu
log=$FAKE_RUNNER_LOG
printf '%s\n' "$1" >>"$log"
exec "$@"
EOF
chmod +x "$work/fake-runner"
runner_log="$work/runner.log"

FAKE_RUNNER_LOG="$runner_log" \
S_STAGE2_COMPILER="$work/fake-stage2" \
S_BOOTSTRAP_SOURCE="$work/compiler.s" \
S_BOOTSTRAP_AS="$work/fake-as" \
S_BOOTSTRAP_LD="$work/fake-ld" \
S_BOOTSTRAP_RUNTIME_OBJECT="$work/runtime.o" \
S_BOOTSTRAP_LINKER_SCRIPT="$work/linker.ld" \
S_BOOTSTRAP_RUNNER="$work/fake-runner" \
S_BOOTSTRAP_TIMEOUT=30 \
    "$script" "$work/runner-out"

runner_report="$work/runner-out/stage2-stage3-memory-report.txt"
grep -q '^runner='"$work"'/fake-runner$' "$runner_report"
grep -q '^phase.compile.status=0$' "$runner_report"
grep -q '^result=PASS_STAGE3_GENERATED$' "$runner_report"
grep -q '^'"$work"'/fake-stage2$' "$runner_log"

printf '%s\n' 'native bootstrap diagnostic checks passed'
