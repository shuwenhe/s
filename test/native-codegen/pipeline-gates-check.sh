#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-pipeline-gates.XXXXXX)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "pipeline gate artifacts: $work" >&2; fi' EXIT

fixture() {
    local directory=$1 compiler=$2
    mkdir -p "$directory/bin"
    ln -s "$compiler" "$directory/bin/s_compiler"
    ln -s "$root/bin/s_seed" "$directory/bin/s_seed"
    ln -s "$root/src" "$directory/src"
    ln -s "$root/test" "$directory/test"
}
expect_pass() {
    local stage=$1 directory=$2 report=$3
    if ! timeout 150s "$root/script/canonical-$stage-check.sh" "$directory" > "$work/$stage-pass.log" 2>&1; then
        cat "$work/$stage-pass.log" >&2
        echo "$stage gate rejected current native production code" >&2
        exit 1
    fi
    grep -Fxq 'scope=P0 Native Linux/amd64' "$report"
    grep -Fxq 'selfhost=NOT_PROVEN' "$report"
    grep -Fxq 'result=PASS' "$report"
}
expect_rejection() {
    local stage=$1 directory=$2 report=$3 name=$4
    if timeout 150s "$root/script/canonical-$stage-check.sh" "$directory" > "$work/$name.log" 2>&1; then
        cat "$work/$name.log" >&2
        echo "$stage gate accepted $name" >&2
        exit 1
    fi
    grep -Fxq 'result=FAIL' "$report"
    grep -q '^first-unmet-contract=' "$report"
    if grep -Eq '^stage(17-codegen|18-regalloc)=CLOSED$' "$report"; then
        echo "$stage gate left closed status for $name" >&2
        exit 1
    fi
}

# The real emitter succeeds today; stale assertions about the retired backend
# must not reject that path. The gate also proves several inputs/source edits.
fixture "$work/real" "$root/bin/s_compiler"
timeout 30s "$root/bin/s_compiler" --emit-amd64 \
    "$root/test/native-build/program.s" "$work/fixed.s"
expect_pass codegen "$work/real" "$work/real/.bootstrap/stage17/canonical-codegen-gate.txt"

# A failed inspector must replace an earlier PASS report with failure evidence.
for tool in readelf objdump; do
    mkdir -p "$work/$tool-failure"
    printf '#!/bin/sh\nexit 23\n' > "$work/$tool-failure/$tool"
    chmod +x "$work/$tool-failure/$tool"
    PATH="$work/$tool-failure:$PATH" expect_rejection codegen "$work/real" \
        "$work/real/.bootstrap/stage17/canonical-codegen-gate.txt" "$tool-failure"
done

for name in no-output fixed-artifact malformed-output compiler-failure; do
    mkdir -p "$work/$name-tool"
    case "$name" in
        no-output) printf '#!/bin/sh\nexit 0\n' > "$work/$name-tool/compiler" ;;
        fixed-artifact)
            cat > "$work/$name-tool/compiler" <<'SH'
#!/bin/sh
cp "$(dirname "$0")/fixed.s" "$3"
SH
            ;;
        malformed-output)
            cat > "$work/$name-tool/compiler" <<'SH'
#!/bin/sh
printf '%s\n' 'invalid assembly output' > "$3"
SH
            ;;
        compiler-failure) printf '#!/bin/sh\nexit 23\n' > "$work/$name-tool/compiler" ;;
    esac
    chmod +x "$work/$name-tool/compiler"
    fixture "$work/$name" "$work/$name-tool/compiler"
    if [ "$name" = fixed-artifact ]; then
        cp "$work/fixed.s" "$work/$name/bin/fixed.s"
    fi
    expect_rejection codegen "$work/$name" \
        "$work/$name/.bootstrap/stage17/canonical-codegen-gate.txt" "$name"
    if [ "$name" = fixed-artifact ]; then
        grep -Fq 'changed input 7: expected 30, got 25' \
            "$work/$name/.bootstrap/stage17/canonical-codegen-gate.txt"
    fi
done

if [ "${1:-all}" = codegen ]; then
    echo 'native codegen gate: real source/input variation passes; invalid producers reject: PASS'
    exit 0
fi
for name in regression-failure empty-regression hung-regression; do
    directory="$work/$name"
    mkdir -p "$directory/bin" "$directory/test/native-codegen"
    ln -s "$root/bin/s_seed" "$directory/bin/s_seed"
    ln -s "$root/bin/s_compiler" "$directory/bin/s_compiler"
    if [ "$name" = regression-failure ]; then
        printf '#!/bin/sh\nexit 23\n' > "$directory/test/native-codegen/check.sh"
    elif [ "$name" = hung-regression ]; then
        printf '#!/bin/sh\nsleep 3\n' > "$directory/test/native-codegen/check.sh"
    else
        printf '#!/bin/sh\nexit 0\n' > "$directory/test/native-codegen/check.sh"
    fi
    S_NATIVE_CODEGEN_GATE_TIMEOUT=1 expect_rejection regalloc "$directory" \
        "$directory/.bootstrap/stage18/canonical-regalloc-gate.txt" "$name"
    if [ "$name" = hung-regression ]; then
        grep -q 'regression exited 124' "$directory/.bootstrap/stage18/canonical-regalloc-gate.txt"
    fi
done
expect_pass regalloc "$root" "$root/.bootstrap/stage18/canonical-regalloc-gate.txt"
grep -Fxq 'S18.2.allocator-type=position-based-stack-slots' \
    "$root/.bootstrap/stage18/canonical-regalloc-gate.txt"
if grep -q 'linear_scan_regalloc_with_spill' "$root/.bootstrap/stage18/canonical-regalloc-gate.txt"; then
    echo 'Stage18 still claims the retired linear-scan allocator' >&2
    exit 1
fi
echo 'native pipeline gates: production succeeds; empty, fixed, malformed and failed producers reject: PASS'
