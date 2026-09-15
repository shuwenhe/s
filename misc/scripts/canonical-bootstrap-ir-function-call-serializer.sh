#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "function-call bootstrap ir serializer: usage <lowered.view> <output.ir>" >&2
    exit 2
fi

input_view=$1
output_ir=$2

if [ ! -s "$input_view" ]; then
    echo "function-call bootstrap ir serializer: missing lowered view input" >&2
    exit 1
fi

if ! grep -q '^canonical-lowered-view version=1$' "$input_view"; then
    echo "function-call bootstrap ir serializer: unsupported lowered view format" >&2
    exit 1
fi

if ! grep -q '^view-role=READ_ONLY$' "$input_view"; then
    echo "function-call bootstrap ir serializer: lowered view is not read-only" >&2
    exit 1
fi

call_target=$(
    awk -F= '$1 == "return-call-target" { value=$2 } END { if (value != "") print value }' "$input_view"
)

if [ -z "$call_target" ]; then
    echo "function-call bootstrap ir serializer: missing direct call target" >&2
    exit 1
fi

case "$call_target" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
        echo "function-call bootstrap ir serializer: non-canonical call target" >&2
        exit 1
        ;;
esac

callee_constant=$(
    awk -v target="$call_target" '
        /^function / { current=$2 }
        /^return-constant=/ {
            if (current == target) {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value }
    ' "$input_view"
)

if [ -z "$callee_constant" ]; then
    echo "function-call bootstrap ir serializer: missing callee return constant" >&2
    exit 1
fi

case "$callee_constant" in
    -[0-9]*|[0-9]*) ;;
    *)
        echo "function-call bootstrap ir serializer: non-canonical callee constant" >&2
        exit 1
        ;;
esac

{
    echo "SSEED-TARGET-V1"
    echo "FUNC_BEGIN|$call_target|_|_"
    echo "RET|$callee_constant|_|_"
    echo "FUNC_END|$call_target|_|_"
    echo "FUNC_BEGIN|main|_|_"
    echo "CALL|call_result|$call_target|0"
    echo "RET|call_result|_|_"
    echo "RET|0|_|_"
    echo "FUNC_END|main|_|_"
} >"$output_ir"
