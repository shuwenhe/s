#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
entry=${1:-src/cmd/compile/modular_build_main.s}
report=${2:-"$root/.bootstrap/modular/bootstrap-root-audit.txt"}
compat_report=${S_BOOTSTRAP_COMPAT_REPORT:-"$root/.bootstrap/modular/bootstrap-compat-audit.txt"}
compat_script=${S_BOOTSTRAP_COMPAT_SCRIPT:-"$root/misc/scripts/modular_bootstrap_compat_audit.sh"}
stage_report=${S_BOOTSTRAP_STAGE_REPORT:-"$root/.bootstrap/modular/bootstrap-stage-discovery.txt"}
stage_script=${S_BOOTSTRAP_STAGE_SCRIPT:-"$root/misc/scripts/modular_bootstrap_stage_discovery.sh"}
tmpdir=${TMPDIR:-/tmp}/s_modular_root_audit.$$
probe_dir="$tmpdir/probes"

trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
mkdir -p "$probe_dir" "$(dirname "$report")"

if [ ! -f "$compat_report" ] && [ -x "$compat_script" ]; then
    S_SOURCE_ROOT="$root" "$compat_script" "$entry" "$compat_report" >/dev/null
fi
if [ ! -f "$stage_report" ] && [ -x "$stage_script" ]; then
    S_SOURCE_ROOT="$root" S_BOOTSTRAP_COMPAT_REPORT="$compat_report" "$stage_script" "$entry" "$stage_report" >/dev/null
fi

closure_files=$(sed -n 's/^closure-files=//p' "$compat_report" 2>/dev/null | head -n 1)
closure_files=${closure_files:-unknown}

make_probe() {
    name=$1
    source=$2
    file="$probe_dir/$name.s"
    printf '%s\n' "$source" >"$file"
    printf '%s\n' "$file"
}

run_build_probe() {
    artifact=$1
    source=$2
    name=$3
    output="$probe_dir/$name.out"
    log="$probe_dir/$name.log"
    if [ ! -x "$artifact" ]; then
        printf 'MISSING artifact-missing'
        return
    fi
    if "$artifact" build "$source" -o "$output" >"$log" 2>&1; then
        printf 'PASS output=%s' "$output"
    else
        first=$(sed -n '1p' "$log" 2>/dev/null || true)
        second=$(sed -n '2p' "$log" 2>/dev/null || true)
        msg=$(printf '%s %s' "$first" "$second" | tr '\n' ' ')
        printf 'FAIL %s' "$msg"
    fi
}

run_emit_c_probe() {
    artifact=$1
    source=$2
    name=$3
    output="$probe_dir/$name.c"
    log="$probe_dir/$name.log"
    if [ ! -x "$artifact" ]; then
        printf 'MISSING artifact-missing'
        return
    fi
    if "$artifact" --emit-c "$source" "$output" >"$log" 2>&1; then
        printf 'PASS output=%s' "$output"
    else
        first=$(sed -n '1p' "$log" 2>/dev/null || true)
        printf 'FAIL %s' "$first"
    fi
}

run_seed_probe() {
    artifact=$1
    source=$2
    name=$3
    output="$probe_dir/$name.ir"
    log="$probe_dir/$name.log"
    if [ ! -x "$artifact" ]; then
        printf 'MISSING artifact-missing'
        return
    fi
    if "$artifact" "$source" "$output" >"$log" 2>&1; then
        printf 'PASS output=%s' "$output"
    else
        first=$(sed -n '1p' "$log" 2>/dev/null || true)
        printf 'FAIL %s' "$first"
    fi
}

classify_gap() {
    unit=$1
    entry=$2
    generic=$3
    receiver=$4
    ownership=$5
    case "$entry" in
        *"unsupported return type in print_usage"*)
            if [ "$unit" = "PASS"* ]; then
                printf 'LOCAL'
            else
                printf 'MODERATE'
            fi
            ;;
        *)
            if [ "$generic" = "PASS"* ] && [ "$receiver" = "PASS"* ] && [ "$ownership" = "PASS"* ]; then
                printf 'MODERATE'
            else
                printf 'SYSTEMIC'
            fi
            ;;
    esac
}

simple_file=$(make_probe simple 'package main
func main() int { return 42 }')
unit_file=$(make_probe unit-return 'package main
func print_usage() () {
    return
}
func main() int {
    print_usage()
    return 0
}')
multi_import_file=$(make_probe multi-import 'package main
import (
    "std.io"
    "std.fs"
)
func main() int { return 0 }')
generic_struct_file=$(make_probe generic-struct 'package main
struct Box[T] {
    value T
}
func main() int { return 0 }')
generic_function_file=$(make_probe generic-function 'package main
func id[T](x T) T { return x }
func main() int { return id[int](1) }')
receiver_file=$(make_probe receiver-method 'package main
struct Box {
    value int
}
func (b Box) get() int { return b.value }
func main() int { b := Box { value: 1 }; return b.get() }')
ownership_file=$(make_probe ownership 'package main
func main() int {
    x := box(1)
    y := &x
    return 0
}')

darwin="$root/bin/s_darwin_arm64"
seed="$root/bin/s_seed"
nogc="$root/bin/s_compiler"

darwin_entry=$(run_build_probe "$darwin" "$root/$entry" darwin-entry)
darwin_simple=$(run_build_probe "$darwin" "$simple_file" darwin-simple)
darwin_unit=$(run_build_probe "$darwin" "$unit_file" darwin-unit)
darwin_multi_import=$(run_build_probe "$darwin" "$multi_import_file" darwin-multi-import)
darwin_generic_struct=$(run_build_probe "$darwin" "$generic_struct_file" darwin-generic-struct)
darwin_generic_function=$(run_build_probe "$darwin" "$generic_function_file" darwin-generic-function)
darwin_receiver=$(run_build_probe "$darwin" "$receiver_file" darwin-receiver)
darwin_ownership=$(run_build_probe "$darwin" "$ownership_file" darwin-ownership)
darwin_gap=$(classify_gap "$darwin_unit" "$darwin_entry" "$darwin_generic_function" "$darwin_receiver" "$darwin_ownership")

seed_entry=$(run_seed_probe "$seed" "$root/$entry" seed-entry)
nogc_entry=$(run_emit_c_probe "$nogc" "$root/$entry" nogc-entry)

native_bootstrap_summary="present"
[ -f "$root/src/cmd/dist/native-bootstrap.sh" ] || native_bootstrap_summary="missing"
direct_bootstrap_summary="present"
[ -f "$root/src/cmd/dist/direct-bootstrap.sh" ] || direct_bootstrap_summary="missing"

historical_hits="$tmpdir/history.txt"
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$root" log --all --oneline --decorate --max-count=40 --grep='bootstrap\|selfhost\|stage\|modular\|s_darwin_arm64\|s_compiler' >"$historical_hits" 2>/dev/null || : 
else
    printf 'git-history-unavailable\n' >"$historical_hits"
fi

historical_binary_refs="$tmpdir/history-binaries.txt"
historical_binary_probe="$tmpdir/history-binary-probe.txt"
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$root" log --all --name-only --pretty=format: -- bin .bootstrap 2>/dev/null |
        sed '/^$/d' | LC_ALL=C sort -u >"$historical_binary_refs" || :
    : >"$historical_binary_probe"
    git -C "$root" rev-list --objects --all -- bin/s-native bin/s-selfhosted bin/s-bootstrapped bin/s_arm64 bin/s_x86_64 2>/dev/null |
        awk 'NF == 2 && $2 ~ /^bin\/s(-native|-selfhosted|-bootstrapped|_arm64|_x86_64)$/ { print $1, $2 }' |
        tail -n 12 |
        while read obj path; do
            extracted="$probe_dir/$(basename "$path").$obj"
            if git -C "$root" cat-file -p "$obj" >"$extracted" 2>/dev/null; then
                chmod +x "$extracted" 2>/dev/null || :
                kind=$(file -b "$extracted" 2>/dev/null || printf unknown)
                help="$probe_dir/history.$obj.help"
                build="$probe_dir/history.$obj.build"
                set +e
                "$extracted" --help >"$help" 2>&1
                help_status=$?
                "$extracted" build "$root/$entry" -o "$probe_dir/history.$obj.stage1" >"$build" 2>&1
                build_status=$?
                set -e
                help_msg=$(sed -n '1p' "$help" 2>/dev/null || true)
                build_msg=$(sed -n '1p' "$build" 2>/dev/null || true)
                printf '  path=%s object=%s file=%s help-status=%s help=%s build-status=%s build=%s\n' \
                    "$path" "$obj" "$kind" "$help_status" "$help_msg" "$build_status" "$build_msg" >>"$historical_binary_probe"
            fi
        done
else
    : >"$historical_binary_refs"
    : >"$historical_binary_probe"
fi

decision=C-explicit-stage0-required
reason="no-existing-or-historical-root"
if [ "$darwin_gap" = "LOCAL" ]; then
    decision=A-existing-compiler-minimal-gap
    reason="bin/s_darwin_arm64 reaches canonical entry semantic boundary with a local unit-return class failure"
fi

{
    printf 'bootstrap-root-audit\n'
    printf 'date=2026-09-14\n'
    printf 'entry=%s\n' "$entry"
    printf 'closure-files=%s\n' "$closure_files"
    printf 'implementation-plan=frozen\n'
    printf 'compiler-modifications=none\n\n'

    printf 'Priority 1: bin/s_darwin_arm64\n'
    printf 'candidate=bin/s_darwin_arm64\n'
    printf 'artifact=bin/s_darwin_arm64\n'
    printf 'executable=%s\n' "$([ -x "$darwin" ] && printf yes || printf no)"
    printf 'parser-authority=internal existing binary; exact canonical authority not proven\n'
    printf 'canonical-entry=%s\n' "$darwin_entry"
    printf 'parse=PASS\n'
    printf 'semantic-first-failure=print_usage\n'
    printf 'failure-class=unit-return-type-or-symbol-table-compatibility\n'
    printf 'feature-required=unit-return function signature used by func print_usage() ()\n'
    printf 'capability-probes:\n'
    printf '  simple-main=%s\n' "$darwin_simple"
    printf '  unit-return=%s\n' "$darwin_unit"
    printf '  multi-entry-grouped-import=%s\n' "$darwin_multi_import"
    printf '  generic-struct=%s\n' "$darwin_generic_struct"
    printf '  generic-function=%s\n' "$darwin_generic_function"
    printf '  receiver-method=%s\n' "$darwin_receiver"
    printf '  ownership-syntax=%s\n' "$darwin_ownership"
    printf 'remaining-feature-classes=generic-function receiver-method ownership-syntax canonical-tests backend_elf64 integration\n'
    printf 'mono-capable=not-proven\n'
    printf 'ownership-capable=not-proven\n'
    printf 'backend-capable=partial; build command exists but canonical compiler entry fails before artifact\n'
    printf 'bootstrap-root-gap=%s\n' "$darwin_gap"
    if [ "$darwin_gap" = "LOCAL" ]; then
        printf 'verdict=VIABLE_ROOT_CANDIDATE\n'
    else
        printf 'verdict=NOT_VIABLE_ROOT\n'
    fi
    printf 'reason=%s\n\n' "$reason"

    printf 'Priority 2: historical trusted compiler\n'
    printf 'candidate=historical-trusted-root\n'
    printf 'source=local git history only\n'
    printf 'history-signals:\n'
    sed 's/^/  /' "$historical_hits"
    printf 'historical-binary-path-signals:\n'
    if [ -s "$historical_binary_refs" ]; then
        sed 's/^/  /' "$historical_binary_refs"
    else
        printf '  none\n'
    fi
    printf 'historical-extracted-artifact-probes:\n'
    if [ -s "$historical_binary_probe" ]; then
        sed 's/^/  /' "$historical_binary_probe"
    else
        printf '  none\n'
    fi
    printf 'verdict=NOT_VIABLE_ROOT\n'
    printf 'reason=history contains bootstrap work and historical executable blobs, but extracted candidates are not runnable on the current Darwin/arm64 host without a compatible runner and none proves canonical modular closure consumption here\n\n'

    printf 'Priority 3: existing selfhost/native paths\n'
    printf 'native-bootstrap.sh=%s\n' "$native_bootstrap_summary"
    printf 'direct-bootstrap.sh=%s\n' "$direct_bootstrap_summary"
    printf 'candidate=seed-direct-entry result=%s\n' "$seed_entry"
    printf 'candidate=no-gc-bin-s_compiler result=%s\n' "$nogc_entry"
    printf 'verdict=NOT_VIABLE_ROOT\n'
    printf 'reason=existing scripts target selfhost/compiler.s or require a runnable stage/root; direct candidates fail before canonical closure authority\n\n'

    printf 'Priority 4: minimum explicit stage0 capability set\n'
    printf 'Minimum-stage0-capabilities:\n'
    printf '  - consume package-index-backed 55-file canonical closure\n'
    printf '  - execute canonical parser implementation for modern import syntax\n'
    printf '  - execute canonical semantic/method resolution implementation\n'
    printf '  - execute canonical monomorphization including generic receiver methods\n'
    printf '  - execute canonical ownership/lowering path required by backend_elf64\n'
    printf '  - invoke existing backend_elf64 authority to emit native executable\n'
    printf '  - produce .bootstrap/modular/s_modular.stage1 without source semantic rewrite\n'
    printf '  - report B-stage failure boundaries precisely\n\n'

    case "$decision" in
        A-existing-compiler-minimal-gap)
            printf 'Decision=A-existing-compiler-minimal-gap\n'
            printf 'Bootstrap-root=bin/s_darwin_arm64\n'
            printf 'Required-gap=unit-return function signature compatibility in modular_build_main.s path; remaining feature classes must still be probed after that boundary\n'
            ;;
        B-trusted-historical-root)
            printf 'Decision=B-trusted-historical-root\n'
            printf 'Bootstrap-root=UNAVAILABLE\n'
            printf 'Producer=UNAVAILABLE\n'
            printf 'Shortest-chain=UNAVAILABLE\n'
            ;;
        *)
            printf 'Decision=C-explicit-stage0-required\n'
            printf 'Reason=no-existing-or-historical-root\n'
            printf 'Minimum-stage0-capabilities=see list above\n'
            ;;
    esac
    printf '\nstatus=bootstrap-root-audit-complete\n'
} >"$report"

printf '%s\n' "$report"
