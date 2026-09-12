#!/bin/sh
set -eu



script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -f "$script_dir/../makefile" ]; then

    root=$(CDPATH= cd -- "$script_dir/.." && pwd)

else

    root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

fi

compiler="$root/bin/s_compiler"
modular_compiler=${S_MODULAR_COMPILER:-"$root/bin/s_modular"}



usage() {

    echo 'usage:' >&2

    echo '  s <input.s>' >&2

    echo '  s <input.s> -o <output>' >&2

    echo '  s -o <output> <input.s>' >&2

    echo '  s build <input.s> -o <output>' >&2
    echo '  s build --legacy <input.s> -o <output>' >&2

    echo '  s --emit-c <input.s> <output.c>' >&2
    echo '  s --emit-mir <input.s> <output.mir>' >&2
    echo '  s --emit-mir-after-drop <input.s> <output.mir>' >&2
    echo '  s --emit-mir-place <input.s> <output.mir>' >&2
    echo '  s --emit-mir-movepath <input.s> <output.mir>' >&2
    echo '  s --emit-mir-partial-move <input.s> <output.mir>' >&2

    echo '  s --seed <input.s> <output.ir>' >&2

    echo '  s --seed --emit-bin <input.ir> <output.bin>' >&2

}



default_output() {

    case "$1" in

        *.s) printf '%s\n' "${1%.*}" ;;

        *) printf '%s.out\n' "$1" ;;

    esac

}



ensure_compiler() {

    if [ ! -x "$compiler" ]; then

        make -C "$root" compiler >/dev/null

    fi

}



emit_binary_legacy() {

    input=$1

    output=$2

    input_abs=$(cd "$(dirname -- "$input")" && pwd)/$(basename -- "$input")

    output_dir=$(dirname -- "$output")

    output_base=$(basename -- "$output")

    mkdir -p "$output_dir"

    output_abs=$(cd "$output_dir" && pwd)/$output_base

    if [ "$input_abs" = "$output_abs" ]; then

        echo "s: output path must not overwrite input source" >&2

        exit 2

    fi

    ensure_compiler

    work=$(mktemp -d "${TMPDIR:-/tmp}/s-nogc.XXXXXXXX")

    trap 'rm -rf "$work"' EXIT HUP INT TERM

    "$compiler" --emit-c "$input" "$work/program.c"

    "${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror ${S_COMPILER_CFLAGS:-} \
        -I "$root/src/runtime" "$work/program.c" -o "$work/program"

    cp "$work/program" "$output"

    chmod +x "$output"

}



emit_binary() {

    input=$1

    output=$2

    if [ -x "$modular_compiler" ]; then

        exec "$modular_compiler" build "$input" -o "$output"

    fi

    if [ "${S_DRIVER_VERBOSE:-}" = "1" ]; then

        echo "s: modular compiler not found; falling back to legacy compiler" >&2

        echo "s: set S_MODULAR_COMPILER or install bin/s_modular to use the modular pipeline" >&2

    fi

    emit_binary_legacy "$input" "$output"

}



if [ "$#" -eq 1 ] && [ "$1" = "--help" ]; then

    usage

    exit 0

fi



if [ "$#" -ge 1 ] && [ "$1" = "--seed" ]; then

    shift

    export S_SOURCE_ROOT="$root"

    exec "$root/bin/s_seed" "$@"

fi



if [ "$#" -eq 3 ] && [ "$1" = "--emit-c" ]; then

    ensure_compiler

    exec "$compiler" "$@"

fi

if [ "$#" -eq 3 ] && [ "$1" = "--emit-mir" ]; then

    ensure_compiler

    exec "$compiler" "$@"

fi

if [ "$#" -eq 3 ] && [ "$1" = "--emit-mir-after-drop" ]; then

    ensure_compiler

    exec "$compiler" "$@"

fi

if [ "$#" -eq 3 ] && [ "$1" = "--emit-mir-place" ]; then

    ensure_compiler

    exec "$compiler" "$@"

fi

if [ "$#" -eq 3 ] && [ "$1" = "--emit-mir-movepath" ]; then

    ensure_compiler

    exec "$compiler" "$@"

fi

if [ "$#" -eq 3 ] && [ "$1" = "--emit-mir-partial-move" ]; then

    ensure_compiler

    exec "$compiler" "$@"

fi



if [ "$#" -eq 1 ]; then

    emit_binary "$1" "$(default_output "$1")"

    exit 0

fi



if [ "$#" -eq 3 ] && [ "$2" = "-o" ]; then

    emit_binary "$1" "$3"

    exit 0

fi



if [ "$#" -eq 3 ] && [ "$1" = "-o" ]; then

    emit_binary "$3" "$2"

    exit 0

fi



if [ "$#" -eq 4 ] && [ "$1" = "build" ] && [ "$3" = "-o" ]; then

    emit_binary "$2" "$4"

    exit 0

fi



if [ "$#" -eq 5 ] && [ "$1" = "build" ] && [ "$2" = "--legacy" ] && [ "$4" = "-o" ]; then

    emit_binary_legacy "$3" "$5"

    exit 0

fi



usage

exit 2
