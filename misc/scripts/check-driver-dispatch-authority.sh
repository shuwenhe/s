#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
compiler="$root/bin/s"

if [ ! -x "$compiler" ]; then
    echo "missing executable compiler: $compiler" >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat >"$work/hello.s" <<'SRC'
package main

func main() int {
    println("driver authority")
    return 0
}
SRC

cat >"$work/production-compiler" <<'SH'
#!/bin/sh
set -eu
echo "production-compiler-argv=$*" >&2
if [ "$#" -eq 4 ] && [ "$1" = "build" ] && [ "$3" = "-o" ]; then
    cat >"$4" <<'OUT'
#!/bin/sh
printf '%s\n' 'driver authority'
OUT
    chmod +x "$4"
    exit 0
fi
echo "unexpected production compiler invocation: $*" >&2
exit 2
SH
chmod +x "$work/production-compiler"

run_and_require_route() {
    name=$1
    expected=$2
    shift 2
    log="$work/$name.log"
    if ! S_DRIVER_AUTHORITY_TRACE=1 S_MODULAR_COMPILER="$work/production-compiler" "$compiler" "$@" >"$work/$name.out" 2>"$log"; then
        echo "command failed unexpectedly: $*" >&2
        cat "$log" >&2
        exit 1
    fi
    if ! grep -F "driver-dispatch=$expected" "$log" >/dev/null 2>&1; then
        echo "missing driver authority marker for $name: driver-dispatch=$expected" >&2
        cat "$log" >&2
        exit 1
    fi
}

run_and_reject_with_route() {
    name=$1
    expected=$2
    shift 2
    log="$work/$name.log"
    if S_DRIVER_AUTHORITY_TRACE=1 S_MODULAR_COMPILER="$work/production-compiler" "$compiler" "$@" >"$work/$name.out" 2>"$log"; then
        echo "command succeeded unexpectedly: $*" >&2
        cat "$log" >&2
        exit 1
    fi
    if ! grep -F "driver-dispatch=$expected" "$log" >/dev/null 2>&1; then
        echo "missing driver authority marker for rejected $name: driver-dispatch=$expected" >&2
        cat "$log" >&2
        exit 1
    fi
}

cd "$work"

run_and_require_route default-build production-build hello.s
[ "$(./hello)" = "driver authority" ]

run_and_require_route output-before-input production-build -o out-before hello.s
[ "$(./out-before)" = "driver authority" ]

run_and_require_route build-subcommand production-build build hello.s -o out-build
[ "$(./out-build)" = "driver authority" ]

run_and_require_route help help --help
grep -F "usage:" "$work/help.log" >/dev/null 2>&1

run_and_require_route legacy-explicit explicit-legacy build --legacy hello.s -o out-legacy
[ "$(./out-legacy)" = "driver authority" ]

run_and_reject_with_route missing-input production-build missing.s
if [ -e missing ]; then
    echo "missing input unexpectedly produced output" >&2
    exit 1
fi

missing_log="$work/missing-production.log"
if S_DRIVER_AUTHORITY_TRACE=1 S_MODULAR_COMPILER="$work/not-present" "$compiler" hello.s -o no-production >"$work/missing-production.out" 2>"$missing_log"; then
    echo "default build unexpectedly succeeded without production compiler" >&2
    cat "$missing_log" >&2
    exit 1
fi
grep -F "driver-dispatch=production-build" "$missing_log" >/dev/null 2>&1
grep -F "implicit-legacy-fallback=NO" "$missing_log" >/dev/null 2>&1
if [ -e no-production ]; then
    echo "missing production compiler unexpectedly produced output" >&2
    exit 1
fi

echo "driver-dispatch-authority=PROVEN"
