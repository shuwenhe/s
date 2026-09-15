#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "cfg branch bootstrap ir serializer: usage <lowered.view> <output.ir>" >&2
    exit 2
fi

input_view=$1
output_ir=$2

if [ ! -s "$input_view" ]; then
    echo "cfg branch bootstrap ir serializer: missing lowered view input" >&2
    exit 1
fi

if ! grep -q '^canonical-lowered-view version=1$' "$input_view"; then
    echo "cfg branch bootstrap ir serializer: unsupported lowered view format" >&2
    exit 1
fi

if ! grep -q '^view-role=READ_ONLY$' "$input_view"; then
    echo "cfg branch bootstrap ir serializer: lowered view is not read-only" >&2
    exit 1
fi

condition=$(
    awk '
        /^function / { current=$2 }
        /^branch-condition=/ {
            if (current == "choose") {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value }
    ' "$input_view"
)
true_value=$(
    awk '
        /^function / { current=$2 }
        /^block / { block=$2 }
        /^return-constant=/ {
            if (current == "choose" && block == "bb1") {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value }
    ' "$input_view"
)
false_value=$(
    awk '
        /^function / { current=$2 }
        /^block / { block=$2 }
        /^return-constant=/ {
            if (current == "choose" && block == "bb2") {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value }
    ' "$input_view"
)
main_arg=$(
    awk -F= '$1 == "call-argument" { value=$2 } END { if (value != "") print value }' "$input_view"
)

if [ -z "$condition" ] || [ -z "$true_value" ] || [ -z "$false_value" ] || [ -z "$main_arg" ]; then
    echo "cfg branch bootstrap ir serializer: missing branch facts" >&2
    exit 1
fi

case "$condition" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
        echo "cfg branch bootstrap ir serializer: non-canonical branch condition" >&2
        exit 1
        ;;
esac

for value in "$true_value" "$false_value" "$main_arg"; do
    case "$value" in
        -[0-9]*|[0-9]*) ;;
        *)
            echo "cfg branch bootstrap ir serializer: non-canonical integer fact" >&2
            exit 1
            ;;
    esac
done

{
    echo "SSEED-TARGET-V1"
    echo "FUNC_BEGIN|choose|_|_"
    echo "PARAM|$condition|_|_"
    echo "JUMP_IF_FALSE|bb2|$condition|_"
    echo "LABEL|bb1|_|_"
    echo "RET|$true_value|_|_"
    echo "LABEL|bb2|_|_"
    echo "RET|$false_value|_|_"
    echo "FUNC_END|choose|_|_"
    echo "FUNC_BEGIN|main|_|_"
    echo "ARG|$main_arg|_|_"
    echo "CALL|call_result|choose|1"
    echo "RET|call_result|_|_"
    echo "RET|0|_|_"
    echo "FUNC_END|main|_|_"
} >"$output_ir"
