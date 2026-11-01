#!/bin/sh
set -eu
compiler=${1:?usage: stage1_source_execution_check.sh COMPILER OUTPUT_DIR}
out=${2:?missing output directory}
mkdir -p "$out"
work=$(mktemp -d "$out/source-execution.XXXXXX")
report=$work/report.txt
failed=0
accept() {
    name=$1 expected=$2 source=$3
    printf '%s\n' "$source" > "$work/$name.s"
    status=0
    "$compiler" build "$work/$name.s" -o "$work/$name" > "$work/$name.build.log" 2>&1 || status=$?
    actual=NOT_RUN
    if [ "$status" -eq 0 ] && [ -x "$work/$name" ]; then
        file -b "$work/$name" > "$work/$name.file.txt"
        if ! grep -Eq 'Mach-O|ELF' "$work/$name.file.txt"; then failed=1; fi
        actual=0
        "$work/$name" > "$work/$name.run.log" 2>&1 || actual=$?
    fi
    printf '%s expected=%s actual=%s build-status=%s\n' "$name" "$expected" "$actual" "$status" >> "$report"
    if [ "$actual" != "$expected" ]; then failed=1; fi
}
reject() {
    name=$1 source=$2
    printf '%s\n' "$source" > "$work/$name.s"
    status=0
    "$compiler" build "$work/$name.s" -o "$work/$name" > "$work/$name.build.log" 2>&1 || status=$?
    printf '%s rejected-status=%s\n' "$name" "$status" >> "$report"
    if [ "$status" -eq 0 ] || [ -e "$work/$name" ]; then failed=1; fi
}
for value in 0 7 17 29 103 255; do
    accept "return$value" "$value" "package main
func main() int { return $value }"
done
accept call17 17 'package main
func value() int { return 17 }
func main() int { return value() }'
accept forward29 29 'package main
func main() int { return value() }
func value() int { return next() }
func next() int { return 29 }'
accept distractors 7 'package main
// return 29
func unused() int { return 17 }
func main () int { /* return 103 */ return (chosen()); }
func chosen() int { return 007 }'
accept template_words 29 'package main
// package cmd modular
func main() int { return 29 }'
reject missing_call 'package main
func main() int { return absent() }'
reject duplicate 'package main
func main() int { return 7 }
func main() int { return 17 }'
reject malformed 'package main
func main( int { return 17 }'
reject trailing 'package main
func main() int { return 17 } garbage'
reject overflow 'package main
func main() int { return 2147483648 }'
reject unterminated 'package main
func main() int { return 17 } /*'
reject arithmetic 'package main
func main() int { return 17 + 12 }'
reject no_main 'package main
func other() int { return 17 }'
reject extra_return 'package main
func main() int { return 7; return 17 }'
reject negative 'package main
func main() int { return -1 }'
accept named_cmd 17 'package cmd
// modular
func main() int { return 17 }'
accept named_library 29 'package library_42
func helper() int { return 29 }
func main() int { return helper() }'
reject package_not_entry 'package helper
func helper() int { return 7 }'
reject package_missing 'func main() int { return 7 }'
reject package_numeric 'package 42
func main() int { return 7 }'
reject package_keyword 'package return
func main() int { return 7 }'
reject package_duplicate 'package cmd
package cmd
func main() int { return 7 }'
reject package_dotted 'package cmd.tool
func main() int { return 7 }'
reject cyclic_calls 'package main
func main() int { return first() }
func first() int { return second() }
func second() int { return first() }'
if [ "$failed" -eq 0 ]; then result=PASS; else result=FAIL; fi
printf '%s\n' "bootstrap-subset-source-execution=$result" \
    'canonical-source-compilation=NOT_PROVEN' \
    'production-compiler-bootstrap=NOT_PROVEN' "evidence-directory=$work" >> "$report"
cp "$report" "$out/stage1-source-execution-report.txt"
cat "$report"
exit "$failed"
