#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: canonical-bootstrap-ir-minimal-serializer.sh <canonical-output.c> <output.ir>" >&2
    exit 2
fi

input_c=$1
output_ir=$2

if [ ! -s "$input_c" ]; then
    echo "minimal bootstrap ir serializer: missing canonical C input" >&2
    exit 1
fi

return_value=$(
    awk '
        /compiler_result = INT64_C\(/ {
            line = $0
            sub(/^.*compiler_result = INT64_C\(/, "", line)
            sub(/\).*$/, "", line)
            print line
            exit
        }
    ' "$input_c"
)

if [ -z "$return_value" ]; then
    echo "minimal bootstrap ir serializer: unsupported canonical slice" >&2
    exit 1
fi

case "$return_value" in
    -[0-9]*|[0-9]*) ;;
    *)
        echo "minimal bootstrap ir serializer: non-canonical return constant" >&2
        exit 1
        ;;
esac

{
    echo "SSEED-TARGET-V1"
    echo "FUNC_BEGIN|main|_|_"
    echo "RET|$return_value|_|_"
    echo "RET|0|_|_"
    echo "FUNC_END|main|_|_"
} >"$output_ir"
