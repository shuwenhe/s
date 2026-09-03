#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/s-benchmark-$$
trap 'rm -rf "$out"' EXIT HUP INT TERM
mkdir -p "$out"

if [ ! -x "$root/bin/s_seed" ]; then
    echo "missing $root/bin/s_seed; run: make -C $root seed-compiler-bin" >&2
    exit 1
fi

cc=${CC:-cc}
go=${GO:-go}
gocache=$out/go-cache
expected_status=128

echo "Building S (seed AOT)..."
"$root/bin/s_seed" "$root/benchmarks/loop.s" "$out/loop.ir"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-aot "$out/loop.ir" "$out/loop-s"

echo "Building C..."
"$cc" -O3 -march=native -o "$out/loop-c" "$root/benchmarks/loop.c"

echo "Building Go..."
GOCACHE="$gocache" GO111MODULE=off "$go" build -trimpath -o "$out/loop-go" "$root/benchmarks/loop.go"

echo
echo "Runtime (lower is better; one run, use repeated runs for conclusions):"
for name in s c go; do
    printf '%-5s ' "$name"
    set +e
    /usr/bin/time -f 'real=%e user=%U sys=%S' "$out/loop-$name" >/dev/null 2>"$out/$name.time"
    status=$?
    set -e
    cat "$out/$name.time"
    if [ "$status" -ne "$expected_status" ]; then
        echo "$name benchmark failed with status $status" >&2
        exit 1
    fi
done

echo
echo "Binary size:"
wc -c "$out/loop-s" "$out/loop-c" "$out/loop-go"
