#!/usr/bin/env bash
# Gates must inspect and execute current native output, not legacy source text.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/s-artifact-gates-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
fixture="$work/repo"
mkdir -p "$fixture/bin" "$fixture/test/native-build"
cp "$root/test/native-build/program.s" "$fixture/test/native-build/program.s"
ln -s "$root/bin/s_compiler" "$fixture/bin/s_compiler"
gates=(canonical-machine-code-check canonical-object-emission-check canonical-linking-check)
for gate in "${gates[@]}"; do
    if ! bash "$root/script/$gate.sh" "$fixture" > "$work/$gate.log" 2>&1; then
        cat "$work/$gate.log" >&2
        echo "$gate rejected the current native compiler" >&2
        exit 1
    fi
    grep -qx 'result=PASS' "$work/$gate.log"
done

rm "$fixture/bin/s_compiler"
printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/s_compiler"
chmod +x "$fixture/bin/s_compiler"
for gate in "${gates[@]}"; do
    if bash "$root/script/$gate.sh" "$fixture" > "$work/$gate.log" 2>&1; then
        echo "$gate accepted a successful command with no artifact" >&2
        exit 1
    fi
    grep -qx 'result=FAIL' "$work/$gate.log"
done

# Valid ELF headers/symbols alone cannot prove source-dependent compilation.
sed 's/left \* right/0/' "$fixture/test/native-build/program.s" > "$work/wrong.s"
"$root/bin/s_compiler" --emit-native-object "$work/wrong.s" "$work/wrong.o" > "$work/compile.log" 2>&1
"$root/bin/s_compiler" build "$work/wrong.s" -o "$work/wrong" >> "$work/compile.log" 2>&1
cat > "$fixture/bin/s_compiler" <<'SH'
#!/bin/sh
case "$1" in
    --emit-native-object) cp "$S_GATE_WRONG_OBJECT" "$3" ;;
    build) cp "$S_GATE_WRONG_BINARY" "$4" ;;
    *) exit 1 ;;
esac
SH
for gate in "${gates[@]}"; do
    if S_GATE_WRONG_OBJECT="$work/wrong.o" S_GATE_WRONG_BINARY="$work/wrong" \
        bash "$root/script/$gate.sh" "$fixture" > "$work/$gate.log" 2>&1; then
        echo "$gate accepted output for a different source" >&2
        exit 1
    fi
    grep -qx 'result=FAIL' "$work/$gate.log"
done
echo 'native machine code, object and linking gate regressions passed'
