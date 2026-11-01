#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: canonical-bootstrap-ir-lowered-view-serializer.sh <lowered.view> <output.ir>" >&2
    exit 2
fi

input_view=$1
output_ir=$2

if [ ! -s "$input_view" ]; then
    echo "lowered-view bootstrap ir serializer: missing lowered view input" >&2
    exit 1
fi

if ! grep -q '^canonical-lowered-view version=1$' "$input_view"; then
    echo "lowered-view bootstrap ir serializer: unsupported lowered view format" >&2
    exit 1
fi

if ! grep -q '^view-role=READ_ONLY$' "$input_view"; then
    echo "lowered-view bootstrap ir serializer: lowered view is not read-only" >&2
    exit 1
fi

if ! grep -q '^function main$' "$input_view"; then
    echo "lowered-view bootstrap ir serializer: minimal slice requires main" >&2
    exit 1
fi

if ! grep -q '^return-kind=int$' "$input_view"; then
    echo "lowered-view bootstrap ir serializer: minimal slice requires int return" >&2
    exit 1
fi

return_value=$(
    awk -F= '$1 == "return-constant" { value=$2 } END { if (value != "") print value }' "$input_view"
)

if [ -z "$return_value" ]; then
    echo "lowered-view bootstrap ir serializer: missing return constant" >&2
    exit 1
fi

case "$return_value" in
    -[0-9]*|[0-9]*) ;;
    *)
        echo "lowered-view bootstrap ir serializer: non-canonical return constant" >&2
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
