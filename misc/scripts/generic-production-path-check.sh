#!/bin/sh
set -eu

root=${S_PROJECT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
stage1=${MODULAR_STAGE1_BIN:-"$root/.bootstrap/modular/s_modular-stage1"}
modular_wrapper=${S_MODULAR_WRAPPER:-"$root/bin/s_modular"}
driver=${S_DRIVER:-"$root/bin/s"}
report=${GENERIC_PRODUCTION_PATH_REPORT:-"$root/.bootstrap/modular/generic-production-path-report.txt"}

mkdir -p "$(dirname -- "$report")"

tmp=${TMPDIR:-/tmp}/generic-production-path.$$
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fixture="$tmp/generic_identity.s"
cat >"$fixture" <<'SRC'
package main

func identity[T](T x) T {
    return x
}

func main() int {
    x := identity[int](42)
    return x
}
SRC

run_build_path() {
    label=$1
    compiler=$2
    mode=$3
    out="$tmp/$label"
    log="$tmp/$label.log"

    build_status=127
    run_exit=NOT_RUN
    build=FAIL
    executable=NO

    if [ -x "$compiler" ]; then
        set +e
        if [ "$mode" = stage1 ] || [ "$mode" = modular ]; then
            S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$compiler" build "$fixture" -o "$out" >"$log" 2>&1
        else
            S_PROJECT_ROOT="$root" S_SOURCE_ROOT="$root/src" "$compiler" "$fixture" -o "$out" >"$log" 2>&1
        fi
        build_status=$?
        set -e
        if [ "$build_status" -eq 0 ]; then
            build=PASS
        fi
        if [ -x "$out" ]; then
            executable=YES
            set +e
            "$out" >/dev/null 2>&1
            run_exit=$?
            set -e
        fi
    else
        echo "missing compiler: $compiler" >"$log"
    fi

    bootstrap_subset=NO
    s_seed=NO
    generic_parser_reached=UNKNOWN
    semantic_reached=UNKNOWN
    monomorphization_reached=UNKNOWN

    if grep -q 'bootstrap-subset:' "$log"; then
        bootstrap_subset=YES
        generic_parser_reached=NO
    fi
    if grep -Eq 's_seed|bin/s_seed' "$log"; then
        s_seed=YES
    fi
    if grep -Eiq 'parse failed|parser|syntax' "$log"; then
        generic_parser_reached=YES
    fi
    if grep -Eiq 'semantic|monomorph' "$log"; then
        semantic_reached=YES
    fi
    if grep -Eiq 'monomorph' "$log"; then
        monomorphization_reached=YES
    fi
    if [ "$build" = PASS ] || [ "$executable" = YES ]; then
        generic_parser_reached=YES
        semantic_reached=YES
        monomorphization_reached=YES
    fi

    {
        echo "$label-compiler=$compiler"
        echo "$label-build=$build"
        echo "$label-build-status=$build_status"
        echo "$label-executable=$executable"
        echo "$label-exit=$run_exit"
        echo "$label-bootstrap-subset-runtime-path=$bootstrap_subset"
        echo "$label-s-seed-runtime-path=$s_seed"
        echo "$label-generic-parser-reached=$generic_parser_reached"
        echo "$label-generic-semantic-reached=$semantic_reached"
        echo "$label-monomorphization-reached=$monomorphization_reached"
        if [ -s "$log" ]; then
            sed "s/^/$label-diagnostic=/" "$log"
        fi
    } >"$tmp/$label.report"
}

run_build_path stage1-direct "$stage1" stage1
run_build_path modular-wrapper "$modular_wrapper" modular
run_build_path production-driver "$driver" driver

stage1_bs=$(grep '^stage1-direct-bootstrap-subset-runtime-path=' "$tmp/stage1-direct.report" | sed 's/.*=//')
wrapper_bs=$(grep '^modular-wrapper-bootstrap-subset-runtime-path=' "$tmp/modular-wrapper.report" | sed 's/.*=//')
driver_bs=$(grep '^production-driver-bootstrap-subset-runtime-path=' "$tmp/production-driver.report" | sed 's/.*=//')

stage1_build=$(grep '^stage1-direct-build=' "$tmp/stage1-direct.report" | sed 's/.*=//')
wrapper_build=$(grep '^modular-wrapper-build=' "$tmp/modular-wrapper.report" | sed 's/.*=//')
driver_build=$(grep '^production-driver-build=' "$tmp/production-driver.report" | sed 's/.*=//')

first_divergence=none
verdict=CANONICAL_PATH_REACHED

if [ "$stage1_bs" = YES ]; then
    first_divergence=stage1-generic-dispatch
    verdict=ROUTING_BLOCKED
elif [ "$wrapper_bs" = YES ]; then
    first_divergence=modular-wrapper-route
    verdict=ROUTING_BLOCKED
elif [ "$driver_bs" = YES ]; then
    first_divergence=production-driver-route
    verdict=ROUTING_BLOCKED
elif [ "$stage1_build" = FAIL ]; then
    first_divergence=stage1-canonical-generic-pipeline
    verdict=CANONICAL_PATH_REACHED
elif [ "$wrapper_build" = FAIL ]; then
    first_divergence=modular-wrapper-after-canonical
    verdict=ROUTING_BLOCKED
elif [ "$driver_build" = FAIL ]; then
    first_divergence=production-driver-after-canonical
    verdict=ROUTING_BLOCKED
fi

{
    echo "generic-production-path-check"
    cat "$tmp/stage1-direct.report"
    cat "$tmp/modular-wrapper.report"
    cat "$tmp/production-driver.report"
    echo "first-divergence=$first_divergence"
    echo "verdict=$verdict"
} >"$report"

cat "$report"

if [ "$verdict" = ROUTING_BLOCKED ]; then
    exit 1
fi
