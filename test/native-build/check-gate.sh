#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d /tmp/s-native-gate.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/test/native-build"
cp "$root/test/native-build/program.s" "$work/test/native-build/program.s"
ln -s /bin/true "$work/bin/s_compiler"
cat > "$work/constant.s" <<'ASM'
.text
.globl _start
_start:
  mov $25, %edi
  mov $60, %eax
  syscall
.section .note.GNU-stack,"",@progbits
ASM
as --64 "$work/constant.s" -o "$work/constant.o"
ld "$work/constant.o" -o "$work/constant"
cat > "$work/bin/s" <<'DRIVER'
#!/bin/sh
cp "$S_GATE_ARTIFACT" "$4"
DRIVER
chmod +x "$work/bin/s"
if S_GATE_ARTIFACT="$work/constant" sh "$root/script/canonical-executable-check.sh" "$work" > "$work/report"; then
    echo 'gate accepted fixed compile-time behavior' >&2; exit 1
fi
grep -qx 'first-unmet-contract=S22.4' "$work/report"
cat > "$work/bin/s" <<'DRIVER'
#!/bin/sh
if [ "$2" = --legacy ]; then cp "$S_GATE_ARTIFACT" "$5"; exit 0; fi
exit 1
DRIVER
if S_GATE_ARTIFACT="$work/constant" sh "$root/script/canonical-executable-check.sh" "$work" > "$work/report"; then
    echo 'gate fell back to legacy' >&2; exit 1
fi
grep -qx 'first-unmet-contract=S22.2' "$work/report"
printf '%s\n' 'Native executable gate rejects fixed behavior and legacy fallback: PASS'
