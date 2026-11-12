#!/bin/sh
set -eu



entry=${1:?usage: source_closure.sh ENTRY OUTPUT}

output=${2:?usage: source_closure.sh ENTRY OUTPUT}

root=${S_SOURCE_ROOT:-$(pwd)}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

mode=${S_CLOSURE_MODE:-production}
case "$mode" in
    production|test) ;;
    *) echo "source_closure: invalid S_CLOSURE_MODE: $mode" >&2; exit 2 ;;
esac

resolver="$root/misc/tools/s_resolver"

tmp="${output}.tmp.$$"

pkg_index="$tmp.pkg"
all_pkg_index="$tmp.all.pkg"

trap 'rm -f "$tmp" "$pkg_index" "$all_pkg_index" "$tmp.queue" "$tmp.seen"' EXIT HUP INT TERM

python3 - "$root/src" "$all_pkg_index" <<'PY'
import re
import sys
from pathlib import Path

source_root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])
package = re.compile(r"^\s*package\s+(\S+)")

with output.open("w", encoding="utf-8") as stream:
    for source_file in sorted(source_root.rglob("*.s")):
        try:
            with source_file.open("r", encoding="utf-8") as source:
                for line in source:
                    match = package.match(line)
                    if match:
                        relative = source_file.relative_to(source_root.parent)
                        stream.write(f"{match.group(1)}\t{relative.as_posix()}\n")
                        break
        except (OSError, UnicodeDecodeError):
            continue
PY

if [ "$mode" = production ]; then
    awk -F '\t' '$2 !~ /[^/]+_test\.s$/ && $2 !~ /\/testdata\// { print }' "$all_pkg_index" >"$pkg_index"
else
    cp "$all_pkg_index" "$pkg_index"
fi

fail_test_dependency() {
    echo "source_closure: production closure depends on test-only package: $1" >&2
    exit 1
}



resolve_module_fallback() {

    module=$1

    module=${module%% as *}

    case "$module" in

        compile.internal)

            printf 'src/cmd/compile/internal/stage5_gate.s\n'

            return 0

            ;;

    esac

    exact=$(awk -F '\t' -v pkg="$module" '$1 == pkg { print $2 }' "$pkg_index")

    if [ -n "$exact" ]; then

        printf '%s\n' "$exact" | sed "s#^$root/##"

        return 0

    fi

    if [ "$mode" = production ] &&
       awk -F '\t' -v pkg="$module" '$1 == pkg { found=1 } END { exit(found ? 0 : 1) }' "$all_pkg_index"; then
        fail_test_dependency "$module"
    fi

    case "$module" in

        compile.internal.*)

            rest=${module#compile.internal.}

            dir=$(printf '%s' "$rest" | tr . /)

            while :; do

                if [ -f "$root/src/cmd/compile/internal/$dir.s" ]; then

                    printf 'src/cmd/compile/internal/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/cmd/compile/internal/$dir/${dir##*/}.s" ]; then

                    printf 'src/cmd/compile/internal/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                case "$dir" in

                    */*) dir=${dir%/*} ;;

                    *) break ;;

                esac

            done

            ;;

        internal.*)

            rest=${module#internal.}

            dir=$(printf '%s' "$rest" | tr . /)

            while :; do

                if [ -f "$root/src/internal/$dir.s" ]; then

                    printf 'src/internal/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/internal/$dir/${dir##*/}.s" ]; then

                    printf 'src/internal/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                case "$dir" in

                    */*) dir=${dir%/*} ;;

                    *) break ;;

                esac

            done

            ;;

        std.*)

            rest=${module#std.}

            dir=$(printf '%s' "$rest" | tr . /)

            while :; do

                if [ -f "$root/src/$dir/${dir##*/}.s" ]; then

                    printf 'src/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                if [ -f "$root/src/$dir.s" ]; then

                    printf 'src/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/std/$dir.s" ]; then

                    printf 'src/std/%s.s\n' "$dir"

                    return 0

                fi

                if [ -f "$root/src/std/$dir/${dir##*/}.s" ]; then

                    printf 'src/std/%s/%s.s\n' "$dir" "${dir##*/}"

                    return 0

                fi

                case "$dir" in

                    */*) dir=${dir%/*} ;;

                    *) break ;;

                esac

            done

            ;;

    esac

    path=$(printf '%s' "$module" | tr . /)

    if [ -f "$root/src/$path.s" ]; then

        printf 'src/%s.s\n' "$path"

    elif [ -f "$root/src/$path/${path##*/}.s" ]; then

        printf 'src/%s/%s.s\n' "$path" "${path##*/}"

    fi

}



if [ "$mode" = test ] && [ "${S_USE_RESOLVER:-}" = "1" ] && [ -x "$resolver" ] && "$resolver" "$root" "$entry" | sed "s#^$root/##" | LC_ALL=C sort -u >"$tmp"; then

    mv "$tmp" "$output"

    trap - EXIT HUP INT TERM

    exit 0

fi



queue="$tmp.queue"

seen="$tmp.seen"

: >"$queue"

: >"$seen"

printf '%s\n' "$entry" >>"$queue"

# A package is a compilation unit, not a single file.  Import traversal
# discovers external packages, but it must also retain every production source
# file belonging to the entry package so same-package declarations (for
# example main.s and driver.s) remain visible to the compiler.
entry_rel=$entry
case "$entry_rel" in
    /*) entry_rel=$(printf '%s\n' "$entry_rel" | sed "s#^$root/##") ;;
esac
entry_file=$entry_rel
case "$entry_file" in /*) ;; *) entry_file="$root/$entry_file" ;; esac
entry_pkg=$(awk '/^[[:space:]]*package[[:space:]]+/ { sub(/^[[:space:]]*package[[:space:]]+/, ""); sub(/[[:space:]].*$/, ""); print; exit }' "$entry_file")
if [ "$entry_pkg" = main ]; then
    # main names unrelated executables throughout the tree. Only siblings of
    # this entry belong to this executable's package.
    entry_dir=$(dirname "$entry_file")
    for sibling in "$entry_dir"/*.s; do
        [ -f "$sibling" ] || continue
        case "$sibling" in *_test.s) [ "$mode" = test ] || continue ;; esac
        sibling_pkg=$(awk '/^[[:space:]]*package[[:space:]]+/ { print $2; exit }' "$sibling")
        [ "$sibling_pkg" != main ] || printf '%s\n' "$sibling" >>"$queue"
    done
elif [ -n "$entry_pkg" ]; then
    { awk -F '\t' -v pkg="$entry_pkg" '$1 == pkg && $2 ~ /\/token\// { print $2 }' "$pkg_index"; \
      awk -F '\t' -v pkg="$entry_pkg" '$1 == pkg && $2 !~ /\/token\// { print $2 }' "$pkg_index"; } |
    while IFS= read -r package_file; do
        [ -n "$package_file" ] && printf '%s\n' "$root/$package_file" >>"$queue"
    done
fi

while IFS= read -r source_path; do

    case "$source_path" in

        /*) rel_path=$(printf '%s\n' "$source_path" | sed "s#^$root/##") ;;

        *) rel_path=$source_path ;;

    esac

    if grep -qxF "$rel_path" "$seen" 2>/dev/null; then

        continue

    fi

    printf '%s\n' "$rel_path" >>"$seen"

    input_file=$rel_path
    case "$input_file" in /*) ;; *) input_file="$root/$input_file" ;; esac
    [ -f "$input_file" ] || continue

    modules=$(python3 "$script_dir/source_imports.py" "$input_file")
    printf '%s\n' "$modules" |
    while IFS= read -r module; do
        [ -n "$module" ] || continue

        resolved=$(resolve_module_fallback "$module")

        if [ -n "$resolved" ]; then

            printf '%s\n' "$resolved" >>"$queue"

        fi

    done

done <"$queue"

LC_ALL=C sort -u "$seen" |
    awk 'BEGIN { token_count = 0 } /\/lexer\/token\/token\.s$/ { token[token_count++] = $0; next } { rest[rest_count++] = $0 } END { for (i = 0; i < token_count; i++) print token[i]; for (i = 0; i < rest_count; i++) print rest[i] }' >"$tmp"

mv "$tmp" "$output"

trap - EXIT HUP INT TERM
