#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(pwd)}
entry=${1:-src/cmd/compile/modular_build_main.s}
report=${2:-"$root/.bootstrap/modular/bootstrap-compat-audit.txt"}
seed=${S_SEED:-"$root/bin/s_seed"}
closure_script=${S_CLOSURE_SCRIPT:-"$root/src/cmd/dist/source_closure.sh"}
tmpdir=${TMPDIR:-/tmp}/s_modular_bootstrap_audit.$$
closure="$tmpdir/closure.txt"
queue="$tmpdir/queue.txt"
seen="$tmpdir/seen.txt"
imports_tmp="$tmpdir/imports.txt"
probe_dir="$tmpdir/probes"
seed_out="$tmpdir/seed-entry.out"
package_index=${S_PACKAGE_INDEX:-"$root/scripts/s-package-index.tsv"}

trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
mkdir -p "$tmpdir" "$probe_dir" "$(dirname "$report")"

resolve_module() {
    module=$1
    module=${module%% as *}
    found=0
    if [ -f "$package_index" ]; then
        awk -F '	' -v pkg="$module" '$1 == pkg { print $2 }' "$package_index" | while IFS= read -r path; do
            case "$path" in
                /*) printf '%s\n' "$path" | sed "s#^$root/##" ;;
                *) printf '%s\n' "$path" ;;
            esac
        done
        found=1
    fi
    case "$module" in
        compile.internal.*)
            path=$(printf '%s' "${module#compile.internal.}" | tr . /)
            [ -f "$root/src/cmd/compile/internal/$path.s" ] && printf 'src/cmd/compile/internal/%s.s\n' "$path"
            [ -f "$root/src/cmd/compile/internal/$path/${path##*/}.s" ] && printf 'src/cmd/compile/internal/%s/%s.s\n' "$path" "${path##*/}"
            ;;
        std.*)
            path=$(printf '%s' "${module#std.}" | tr . /)
            [ -f "$root/src/std/$path.s" ] && printf 'src/std/%s.s\n' "$path"
            [ -f "$root/src/std/$path/${path##*/}.s" ] && printf 'src/std/%s/%s.s\n' "$path" "${path##*/}"
            ;;
        *)
            path=$(printf '%s' "$module" | tr . /)
            [ -f "$root/src/$path.s" ] && printf 'src/%s.s\n' "$path"
            [ -f "$root/src/$path/${path##*/}.s" ] && printf 'src/%s/%s.s\n' "$path" "${path##*/}"
            ;;
    esac
    return "$found"
}

extract_imports() {
    file=$1
    {
        awk '
            /^[[:space:]]*import[[:space:]]*\(/ { in_import=1; next }
            in_import && /^[[:space:]]*\)/ { in_import=0; next }
            in_import { print }
            /^[[:space:]]*import[[:space:]]*"/ { print }
        ' "$file" | sed -n 's/.*"\([^"]*\)".*/\1/p'
        sed -n 's/^[[:space:]]*use[[:space:]]\{1,\}\([^[:space:];]*\).*/\1/p' "$file"
    } | sed '/^$/d' | LC_ALL=C sort -u
}

: >"$queue"
: >"$seen"
printf '%s\n' "$entry" >>"$queue"
while IFS= read -r source_path; do
    case "$source_path" in
        /*) rel=$(printf '%s\n' "$source_path" | sed "s#^$root/##") ;;
        *) rel=$source_path ;;
    esac
    [ -n "$rel" ] || continue
    if grep -qxF "$rel" "$seen" 2>/dev/null; then
        continue
    fi
    printf '%s\n' "$rel" >>"$seen"
    file="$root/$rel"
    [ -f "$file" ] || continue
    extract_imports "$file" >"$imports_tmp"
    while IFS= read -r module; do
        resolve_module "$module" | while IFS= read -r resolved; do
            [ -n "$resolved" ] && printf '%s\n' "$resolved" >>"$queue"
        done
    done <"$imports_tmp"
done <"$queue"

if [ -x "$closure_script" ]; then
    dist_closure="$tmpdir/dist-closure.txt"
    S_SOURCE_ROOT="$root" "$closure_script" "$entry" "$dist_closure" >/dev/null 2>&1 || : 
    [ -f "$dist_closure" ] && cat "$dist_closure" >>"$seen"
fi
LC_ALL=C sort -u "$seen" >"$closure"

count_feature() {
    pattern=$1
    count=0
    while IFS= read -r rel; do
        file="$root/$rel"
        [ -f "$file" ] || continue
        hits=$(grep -E "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' ')
        count=$((count + hits))
    done <"$closure"
    printf '%s\n' "$count"
}

count_multi_import_blocks() {
    count=0
    while IFS= read -r rel; do
        file="$root/$rel"
        [ -f "$file" ] || continue
        hits=$(awk '
            /^[[:space:]]*import[[:space:]]*\(/ { in_import=1; strings=0; next }
            in_import && /^[[:space:]]*\)/ { if (strings > 1) multi++; in_import=0; next }
            in_import && /"/ { strings++ }
            END { print multi + 0 }
        ' "$file")
        count=$((count + hits))
    done <"$closure"
    printf '%s\n' "$count"
}

probe_seed() {
    name=$1
    source=$2
    file="$probe_dir/$name.s"
    ir="$probe_dir/$name.ir"
    out="$probe_dir/$name.out"
    printf '%s\n' "$source" >"$file"
    if "$seed" "$file" "$ir" >"$out" 2>&1; then
        printf 'PASS'
    else
        printf 'FAIL'
    fi
}

probe_emit_c() {
    compiler=$1
    source=$2
    out="$probe_dir/$(basename "$compiler").$(basename "$source").out"
    artifact="$probe_dir/$(basename "$compiler").$(basename "$source").c"
    if [ ! -x "$compiler" ]; then
        printf 'MISSING'
        return
    fi
    if "$compiler" --emit-c "$root/$source" "$artifact" >"$out" 2>&1; then
        printf 'PASS'
    else
        first=$(sed -n '1p' "$out")
        printf 'FAIL %s' "$first"
    fi
}

stage_line() {
    path=$1
    label=$2
    full="$root/$path"
    if [ -x "$full" ]; then
        kind=$(file -b "$full" 2>/dev/null || printf 'unknown')
        printf '%s=%s executable %s\n' "$label" "$path" "$kind"
    elif [ -e "$full" ]; then
        kind=$(file -b "$full" 2>/dev/null || printf 'unknown')
        printf '%s=%s present-not-executable %s\n' "$label" "$path" "$kind"
    else
        printf '%s=%s missing\n' "$label" "$path"
    fi
}

entry_status=PASS
if ! "$seed" "$root/$entry" "$tmpdir/entry.ir" >"$seed_out" 2>&1; then
    entry_status=FAIL
fi
failed_line=$(sed -n 's/.* at \([0-9][0-9]*\):[0-9][0-9]*.*/\1/p' "$seed_out" | head -n 1)
failed_file=$entry
failed_feature=none
if [ "$entry_status" = "FAIL" ]; then
    if [ -n "$failed_line" ]; then
        failed_text=$(sed -n "${failed_line}p" "$root/$entry" 2>/dev/null || true)
        case "$failed_text" in
            *\"*) failed_feature=multi-entry-grouped-import ;;
            *"import ("*) failed_feature=grouped-import ;;
            *"struct "*\[* ) failed_feature=generic-struct ;;
            *"func "*\[* ) failed_feature=generic-function ;;
            *"func ("*) failed_feature=receiver-method ;;
            *) failed_feature=bootstrap-dialect-gap ;;
        esac
    else
        failed_feature=bootstrap-dialect-gap
    fi
fi

closure_files=$(wc -l <"$closure" | tr -d ' ')
grouped_import=$(count_feature '^[[:space:]]*import[[:space:]]*\(')
multi_grouped_import=$(count_multi_import_blocks)
qualified_import=$(count_feature '"[A-Za-z0-9_]+\.[A-Za-z0-9_.]*"')
generic_struct=$(count_feature '^[[:space:]]*(pub[[:space:]]+)?struct[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\[')
generic_function=$(count_feature '^[[:space:]]*(pub[[:space:]]+)?func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\[')
receiver_method=$(count_feature '^[[:space:]]*(pub[[:space:]]+)?func[[:space:]]*\(')
new_literal=$(count_feature '(^|[^:]):[[:space:]]*[^=]')
enum_match=$(count_feature '(^|[[:space:]])(enum|match|switch)([[:space:]]|$)')
ownership=$(count_feature '(&mut|move[[:space:]]|\*|defer|sroutine|borrow)')
new_expr=$(count_feature '(:=|=>|::|match|switch|for[[:space:]]|while[[:space:]]|defer|sroutine)')

probe_grouped=$(probe_seed grouped-import 'package main
import (
    "std.io"
)
func main() int { return 0 }')
probe_multi_grouped=$(probe_seed multi-grouped-import 'package main
import (
    "std.io"
    "std.fs"
)
func main() int { return 0 }')
probe_qualified_use=$(probe_seed qualified-use 'package main
use std.io
func main() int { return 0 }')
probe_generic_struct=$(probe_seed generic-struct 'package main
struct Box[T] {
    value T
}
func main() int { return 0 }')
probe_generic_function=$(probe_seed generic-function 'package main
func id[T](x T) T { return x }
func main() int { return id[int](1) }')
probe_receiver=$(probe_seed receiver-method 'package main
struct Box {
    value int
}
func (b Box) get() int { return b.value }
func main() int { b := Box { value: 1 }; return b.get() }')
probe_literal=$(probe_seed named-literal 'package main
struct Box {
    value int
}
func main() int { b := Box { value: 1 }; return b.value }')
probe_enum=$(probe_seed enum 'package main
enum Color {
    Red = 1
}
func main() int { return Red }')
probe_ownership=$(probe_seed ownership 'package main
func main() int { x := box(1); y := &x; return 0 }')
probe_switch=$(probe_seed switch 'package main
func main() int { x := 1; switch x { case 1: return 42 default: return 0 } }')
probe_s_compiler_entry=$(probe_emit_c "$root/bin/s_compiler" "$entry")
probe_s_compiler_frontend_parser=$(probe_emit_c "$root/bin/s_compiler" "src/cmd/compile/internal/frontend/parser.s")
probe_s_wrapper_entry=$(probe_emit_c "$root/bin/s" "$entry")

unsupported_required=0
[ "$multi_grouped_import" -gt 0 ] && [ "$probe_multi_grouped" = "FAIL" ] && unsupported_required=$((unsupported_required + 1))
[ "$generic_struct" -gt 0 ] && [ "$probe_generic_struct" = "FAIL" ] && unsupported_required=$((unsupported_required + 1))
[ "$generic_function" -gt 0 ] && [ "$probe_generic_function" = "FAIL" ] && unsupported_required=$((unsupported_required + 1))
[ "$receiver_method" -gt 0 ] && [ "$probe_receiver" = "FAIL" ] && unsupported_required=$((unsupported_required + 1))

if [ "$unsupported_required" -le 1 ]; then
    decision="minimal-seed-compatibility-extension"
else
    decision="staged-bootstrap-bridge"
fi

{
    printf 'bootstrap-stage=seed\n'
    printf 'entry=%s\n\n' "$entry"
    printf 'closure-files=%s\n' "$closure_files"
    printf 'parsed-files=0\n'
    printf 'failed-file=%s\n' "$failed_file"
    printf 'failed-line=%s\n' "${failed_line:-unknown}"
    printf 'failed-feature=%s\n\n' "$failed_feature"
    printf 'parse=%s\n' "$entry_status"
    printf 'semantic=NOT_RUN\n'
    printf 'mono=NOT_RUN\n'
    printf 'backend=NOT_RUN\n\n'
    if [ "$entry_status" = "FAIL" ]; then
        printf 'seed-error:\n'
        sed 's/^/  /' "$seed_out"
        printf '\n'
    fi
    printf 'Feature                         closure-count seed-support\n'
    printf '%s\n' '----------------------------------------------------------'
    printf '%-31s %13s %s\n' 'grouped import' "$grouped_import" "$probe_grouped"
    printf '%-31s %13s %s\n' 'multi-entry grouped import' "$multi_grouped_import" "$probe_multi_grouped"
    printf '%-31s %13s %s\n' 'module-qualified import/use' "$qualified_import" "$probe_qualified_use"
    printf '%-31s %13s %s\n' 'generic struct' "$generic_struct" "$probe_generic_struct"
    printf '%-31s %13s %s\n' 'generic function' "$generic_function" "$probe_generic_function"
    printf '%-31s %13s %s\n' 'receiver method' "$receiver_method" "$probe_receiver"
    printf '%-31s %13s %s\n' 'new literal syntax' "$new_literal" "$probe_literal"
    printf '%-31s %13s %s\n' 'new enum/match' "$enum_match" "enum:$probe_enum switch:$probe_switch"
    printf '%-31s %13s %s\n' 'ownership syntax' "$ownership" "$probe_ownership"
    printf '%-31s %13s %s\n\n' 'new expression forms' "$new_expr" "$probe_switch"
    printf 'Existing stages:\n'
    stage_line bin/s_seed bin-s_seed
    stage_line bin/s_compiler bin-s_compiler
    stage_line bin/s bin-s
    stage_line bin/s_modular bin-s_modular
    stage_line .bootstrap/selfhost/native/stage1 selfhost-native-stage1
    stage_line .bootstrap/selfhost/native/stage2 selfhost-native-stage2
    stage_line .bootstrap/selfhost/native/stage3 selfhost-native-stage3
    stage_line .bootstrap/selfhost/slice1/compiler selfhost-slice1-compiler
    stage_line .bootstrap/selfhost/slice2/compiler selfhost-slice2-compiler
    stage_line .bootstrap/selfhost/slice3/compiler selfhost-slice3-compiler
    stage_line .bootstrap/selfhost/slice4/compiler selfhost-slice4-compiler
    stage_line .bootstrap/selfhost/native-codegen/compiler selfhost-native-codegen
    stage_line .bootstrap/modular/s_modular modular-canonical
    printf '\nIntermediate stage capability probes:\n'
    printf 'bin/s_compiler modular-entry=%s\n' "$probe_s_compiler_entry"
    printf 'bin/s_compiler frontend-parser=%s\n' "$probe_s_compiler_frontend_parser"
    printf 'bin/s wrapper modular-entry=%s\n' "$probe_s_wrapper_entry"
    printf '\nDependency closure:\n'
    sed 's/^/  - /' "$closure"
    printf '\nDecision=%s\n' "$decision"
    if [ "$decision" = "minimal-seed-compatibility-extension" ]; then
        printf 'Decision-note=required unsupported surface appears small; extend seed only for bridge syntax, not parser/semantic/mono/backend duplication.\n'
    else
        printf 'Decision-note=dependency closure requires multiple modern dialect features; prefer an existing staged compiler or a thin bootstrap bridge over growing seed into canonical compiler.\n'
    fi
    printf 'status=blocked-bootstrap-compatibility\n'
} >"$report"

printf '%s\n' "$report"
