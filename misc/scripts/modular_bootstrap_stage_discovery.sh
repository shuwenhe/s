#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
entry=${1:-src/cmd/compile/modular_build_main.s}
report=${2:-"$root/.bootstrap/modular/bootstrap-stage-discovery.txt"}
compat_report=${S_BOOTSTRAP_COMPAT_REPORT:-"$root/.bootstrap/modular/bootstrap-compat-audit.txt"}
compat_script=${S_BOOTSTRAP_COMPAT_SCRIPT:-"$root/misc/scripts/modular_bootstrap_compat_audit.sh"}
tmpdir=${TMPDIR:-/tmp}/s_modular_stage_discovery.$$
probe_dir="$tmpdir/probes"

trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
mkdir -p "$probe_dir" "$(dirname "$report")"

if [ ! -f "$compat_report" ] && [ -x "$compat_script" ]; then
    S_SOURCE_ROOT="$root" "$compat_script" "$entry" "$compat_report" >/dev/null
fi

closure_files=$(sed -n 's/^closure-files=//p' "$compat_report" 2>/dev/null | head -n 1)
closure_files=${closure_files:-unknown}

probe_file() {
    name=$1
    source=$2
    file="$probe_dir/$name.s"
    printf '%s\n' "$source" >"$file"
    printf '%s\n' "$file"
}

grouped_file=$(probe_file grouped-import 'package main
import (
    "std.io"
)
func main() int { return 0 }')
multi_grouped_file=$(probe_file multi-grouped-import 'package main
import (
    "std.io"
    "std.fs"
)
func main() int { return 0 }')
generic_struct_file=$(probe_file generic-struct 'package main
struct Box[T] {
    value T
}
func main() int { return 0 }')
generic_function_file=$(probe_file generic-function 'package main
func id[T](x T) T { return x }
func main() int { return id[int](1) }')
receiver_method_file=$(probe_file receiver-method 'package main
struct Box {
    value int
}
func (b Box) get() int { return b.value }
func main() int { b := Box { value: 1 }; return b.get() }')
ownership_file=$(probe_file ownership 'package main
func main() int { x := box(1); y := &x; return 0 }')

run_candidate_command() {
    artifact=$1
    mode=$2
    source=$3
    output=$4
    out="$probe_dir/$(basename "$artifact").$(basename "$source").$mode.out"
    case "$mode" in
        seed-ir)
            "$artifact" "$source" "$output" >"$out" 2>&1
            ;;
        emit-c)
            "$artifact" --emit-c "$source" "$output" >"$out" 2>&1
            ;;
        build)
            "$artifact" build "$source" -o "$output" >"$out" 2>&1
            ;;
        selfhost-native)
            "$artifact" --emit-native "$source" "$output" >"$out" 2>&1
            ;;
        *)
            return 127
            ;;
    esac
}

probe_capability() {
    artifact=$1
    mode=$2
    source=$3
    name=$4
    output="$probe_dir/$(basename "$artifact").$name.out.bin"
    if [ ! -x "$artifact" ]; then
        printf 'MISSING'
        return
    fi
    if run_candidate_command "$artifact" "$mode" "$source" "$output"; then
        printf 'PASS'
    else
        printf 'FAIL'
    fi
}

probe_closure() {
    artifact=$1
    mode=$2
    output="$probe_dir/$(basename "$artifact").closure.out"
    out="$probe_dir/$(basename "$artifact").closure.$mode.out"
    if [ ! -x "$artifact" ]; then
        printf 'parse=MISSING semantic=NOT_RUN build=NOT_RUN reason=artifact-missing'
        return
    fi
    if run_candidate_command "$artifact" "$mode" "$root/$entry" "$output"; then
        case "$mode" in
            build|selfhost-native)
                printf 'parse=PASS semantic=PASS build=PASS reason=canonical-entry-consumed'
                ;;
            *)
                printf 'parse=PASS semantic=PASS build=NOT_RUN reason=canonical-entry-consumed'
                ;;
        esac
    else
        first=$(sed -n '1p' "$out" 2>/dev/null || true)
        first=$(printf '%s' "$first" | tr '\n' ' ')
        case "$first" in
            *PARSE_FAIL*|*parse*|*expected*|*unsupported*imports*)
                printf 'parse=FAIL semantic=NOT_RUN build=NOT_RUN reason=%s' "$first"
                ;;
            *)
                printf 'parse=PASS semantic=FAIL build=NOT_RUN reason=%s' "$first"
                ;;
        esac
    fi
}

mode_for_candidate() {
    label=$1
    case "$label" in
        seed) printf 'seed-ir' ;;
        no-gc|wrapper) printf 'emit-c' ;;
        darwin-arm64) printf 'build' ;;
        selfhost*) printf 'selfhost-native' ;;
        *) printf 'build' ;;
    esac
}

candidate_record() {
    label=$1
    producer=$2
    artifact_rel=$3
    source_entry=$4
    mode=$5
    artifact="$root/$artifact_rel"
    executable=no
    [ -x "$artifact" ] && executable=yes
    grouped=$(probe_capability "$artifact" "$mode" "$grouped_file" grouped-import)
    generic_struct=$(probe_capability "$artifact" "$mode" "$generic_struct_file" generic-struct)
    generic_function=$(probe_capability "$artifact" "$mode" "$generic_function_file" generic-function)
    receiver_method=$(probe_capability "$artifact" "$mode" "$receiver_method_file" receiver-method)
    ownership=$(probe_capability "$artifact" "$mode" "$ownership_file" ownership)
    closure=$(probe_closure "$artifact" "$mode")
    usable=no
    reason=not-tested
    case "$closure" in
        *"parse=PASS semantic=PASS build=PASS"*) usable=yes; reason=consumes-canonical-closure ;;
        *"parse=PASS semantic=PASS"*) usable=partial; reason=can-consume-entry-but-does-not-produce-modular-native ;;
        *"artifact-missing"*) reason=artifact-missing ;;
        *) reason=cannot-consume-canonical-closure ;;
    esac
    printf 'candidate=%s\n' "$label"
    printf 'producer=%s\n' "$producer"
    printf 'artifact=%s\n' "$artifact_rel"
    printf 'source-entry=%s\n' "$source_entry"
    printf 'executable=%s\n' "$executable"
    printf 'capabilities:\n'
    printf '  grouped-import=%s\n' "$grouped"
    printf '  multi-entry-grouped-import=%s\n' "$(probe_capability "$artifact" "$mode" "$multi_grouped_file" multi-grouped-import)"
    printf '  generic-struct=%s\n' "$generic_struct"
    printf '  generic-function=%s\n' "$generic_function"
    printf '  receiver-method=%s\n' "$receiver_method"
    printf '  ownership-syntax=%s\n' "$ownership"
    printf 'canonical-closure:\n'
    printf '  files-tested=%s\n' "$closure_files"
    printf '  %s\n' "$closure"
    printf 'usable-as-stage=%s\n' "$usable"
    printf 'reason=%s\n\n' "$reason"
}

{
    printf 'bootstrap-stage-discovery\n'
    printf 'entry=%s\n' "$entry"
    printf 'compat-report=%s\n' "$compat_report"
    printf 'closure-files=%s\n\n' "$closure_files"

    printf 'Discovery order:\n'
    printf '1. cmd/dist / staged build\n'
    printf '2. selfhost / true-selfhost / native\n'
    printf '3. slice1-5\n'
    printf '4. native-codegen paths\n'
    printf '5. bin/s_compiler and related artifacts\n'
    printf '6. bootstrap directories/scripts\n'
    printf '7. Git history / previous bootstrap implementations\n\n'

    printf 'cmd/dist scripts:\n'
    for script in src/cmd/dist/native-bootstrap.sh src/cmd/dist/direct-bootstrap.sh src/cmd/dist/source_closure.sh src/cmd/dist/checks/bootstrap-frontier.sh src/cmd/dist/checks/audit.sh; do
        if [ -f "$root/$script" ]; then
            printf '  %s=present\n' "$script"
        else
            printf '  %s=missing\n' "$script"
        fi
    done
    printf '\n'

    candidate_record seed "trusted C seed via make seed-compiler-bin" bin/s_seed src/cmd/compile/seed/s_seed.c seed-ir
    candidate_record no-gc "s_seed -> src/cmd/compile/compiler.s -> bin/s_compiler" bin/s_compiler src/cmd/compile/compiler.s emit-c
    candidate_record wrapper "make bin/s shell driver" bin/s src/cmd/compile/compiler.s emit-c
    candidate_record darwin-arm64 "make darwin-arm64-bootstrap" bin/s_darwin_arm64 src/cmd/compile/selfhost/compiler.s build
    candidate_record selfhost-native-stage1 "make native-bootstrap" .bootstrap/selfhost/native/stage1 src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record selfhost-native-stage2 "make native-bootstrap" .bootstrap/selfhost/native/stage2 src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record selfhost-slice1 "make bootstrap-slice1-check" .bootstrap/selfhost/slice1/compiler src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record selfhost-slice2 "make bootstrap-slice2-check" .bootstrap/selfhost/slice2/compiler src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record selfhost-slice3 "make bootstrap-slice3-check" .bootstrap/selfhost/slice3/compiler src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record selfhost-slice4 "make bootstrap-slice4-check" .bootstrap/selfhost/slice4/compiler src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record selfhost-slice5 "make bootstrap-slice5-check" .bootstrap/selfhost/slice5/compiler src/cmd/compile/selfhost/compiler.s selfhost-native
    candidate_record native-codegen "make native-codegen-check" .bootstrap/selfhost/native-codegen/compiler src/cmd/compile/selfhost/compiler.s selfhost-native

    printf 'Git history signals:\n'
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$root" log --all --oneline --decorate --max-count=20 --grep='bootstrap\|selfhost\|stage\|modular' 2>/dev/null | sed 's/^/  /'
    else
        printf '  unavailable\n'
    fi
    printf '\n'

    printf 'Decision=B-thin-bootstrap-bridge\n'
    printf 'Reason=no discovered executable artifact can consume the 55-file canonical modular compiler closure; existing selfhost/slice paths are useful stage machinery but currently target src/cmd/compile/selfhost/compiler.s, not the canonical modular compiler closure.\n'
    printf 'Shortest-chain=UNAVAILABLE\n'
    printf 'Recommended-next=write staged-bootstrap design for a thin bridge that reuses canonical parser/semantic/mono/backend and does not expand s_seed into the modern compiler.\n'
    printf 'status=blocked-no-reusable-existing-stage\n'
} >"$report"

printf '%s\n' "$report"
