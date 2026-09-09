#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out=${TMPDIR:-/tmp}/s-benchmark-$$
trap 'rm -rf "$out"' EXIT HUP INT TERM
mkdir -p "$out"

if [ ! -x "$root/bin/s" ]; then
    echo "missing $root/bin/s; run: make -C $root compiler" >&2
    exit 1
fi

cc=${CC:-cc}
go=${GO:-go}
rustc=${RUSTC:-rustc}
gocache=$out/go-cache
expected_status=128

echo "Building S no-GC..."
"$root/bin/s" "$root/test/benchmarks/loop.s" -o "$out/loop-s"

echo "Building C..."
"$cc" -O3 -march=native -o "$out/loop-c" "$root/test/benchmarks/loop.c"

names="s c"

if command -v "$rustc" >/dev/null 2>&1; then
    echo "Building Rust..."
    "$rustc" -C opt-level=3 -C debuginfo=0 "$root/test/benchmarks/loop.rs" -o "$out/loop-rust"
    names="$names rust"
else
    echo "Skipping Rust: rustc not found"
fi

if command -v "$go" >/dev/null 2>&1; then
    echo "Building Go..."
    GOCACHE="$gocache" GO111MODULE=off "$go" build -trimpath -o "$out/loop-go" "$root/test/benchmarks/loop.go"
    names="$names go"
else
    echo "Skipping Go: go not found"
fi

if nm "$out/loop-s" | grep -E 'runtime_gc|run_gc|mark_roots|sweep_pass|runtime_execute|SSEED|gc_' >/dev/null; then
    echo "S no-GC benchmark linked GC or seed runtime symbols" >&2
    exit 1
fi

echo
echo "Runtime (lower is better; single run, use repeated runs for claims):"
for name in $names; do
    printf '%-5s ' "$name"
    set +e
    if /usr/bin/time -f 'real=%e user=%U sys=%S' "$out/loop-$name" >/dev/null 2>"$out/$name.time"; then
        status=0
    else
        status=$?
    fi
    if grep -q 'illegal option' "$out/$name.time" 2>/dev/null; then
        set +e
        /usr/bin/time "$out/loop-$name" >/dev/null 2>"$out/$name.time"
        status=$?
        set -e
    fi
    set -e
    cat "$out/$name.time"
    if [ "$status" -ne "$expected_status" ]; then
        echo "$name benchmark failed with status $status" >&2
        exit 1
    fi
done

echo
echo "Binary size:"
for name in $names; do
    wc -c "$out/loop-$name"
done
