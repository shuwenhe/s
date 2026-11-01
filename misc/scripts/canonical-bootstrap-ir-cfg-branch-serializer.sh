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

loop_function=$(
    awk '
        /^function / { current=$2 }
        /^loop-header=/ { if (current != "") value=current }
        END { if (value != "") print value }
    ' "$input_view"
)

if [ -n "$loop_function" ]; then
    loop_header=$(
        awk -v fn="$loop_function" '
            /^function / { current=$2 }
            current == fn && /^loop-header=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_condition=$(
        awk -v fn="$loop_function" '
            /^function / { current=$2 }
            current == fn && /^loop-condition=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_body=$(
        awk -v fn="$loop_function" '
            /^function / { current=$2 }
            current == fn && /^loop-body-edge=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_exit=$(
        awk -v fn="$loop_function" '
            /^function / { current=$2 }
            current == fn && /^loop-exit-edge=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_backedge=$(
        awk -v fn="$loop_function" '
            /^function / { current=$2 }
            current == fn && /^loop-backedge=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_return=$(
        awk -v fn="$loop_function" -v exit_block="$loop_exit" '
            /^function / { current=$2 }
            /^block / { block=$2 }
            current == fn && block == exit_block && /^return-constant=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_initial_condition=$(
        awk -v fn="$loop_function" '
            /^function / { current=$2 }
            current == fn && /^loop-initial-condition=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )
    loop_body_move=$(
        awk -v fn="$loop_function" -v body_block="$loop_body" '
            /^function / { current=$2 }
            /^block / { block=$2 }
            current == fn && block == body_block && /^body-move=/ { split($0, parts, "="); value=parts[2] }
            END { if (value != "") print value }
        ' "$input_view"
    )

    if [ -z "$loop_header" ] || [ -z "$loop_condition" ] || [ -z "$loop_body" ] || [ -z "$loop_exit" ] || [ -z "$loop_backedge" ]; then
        echo "cfg branch bootstrap ir serializer: missing loop facts" >&2
        exit 1
    fi

    if ! grep -q '^loop-header-origin=canonical-mir$' "$input_view" ||
       ! grep -q '^loop-condition-origin=canonical-mir-terminator$' "$input_view" ||
       ! grep -q '^loop-body-edge-origin=canonical-mir-terminator$' "$input_view" ||
       ! grep -q '^loop-exit-edge-origin=canonical-mir-terminator$' "$input_view" ||
       ! grep -q '^loop-backedge-origin=canonical-mir$' "$input_view"; then
        echo "cfg branch bootstrap ir serializer: non-canonical loop origin" >&2
        exit 1
    fi

    case "$loop_condition" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
            echo "cfg branch bootstrap ir serializer: non-canonical loop condition" >&2
            exit 1
            ;;
    esac

    for target in "$loop_header" "$loop_body" "$loop_exit" "$loop_backedge"; do
        case "$target" in
            *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
                echo "cfg branch bootstrap ir serializer: non-canonical loop target" >&2
                exit 1
                ;;
            bb*) ;;
            *)
                echo "cfg branch bootstrap ir serializer: non-canonical loop target" >&2
                exit 1
            ;;
        esac
    done

    if [ -n "$loop_initial_condition" ]; then
        if ! grep -q '^loop-initial-condition-origin=canonical-lowered-view$' "$input_view"; then
            echo "cfg branch bootstrap ir serializer: non-canonical loop initializer origin" >&2
            exit 1
        fi
        case "$loop_initial_condition" in
            true|false|-[0-9]*|[0-9]*) ;;
            *)
                echo "cfg branch bootstrap ir serializer: non-canonical loop initializer" >&2
                exit 1
                ;;
        esac
    fi

    body_move_target=
    body_move_value=
    if [ -n "$loop_body_move" ]; then
        if ! grep -q '^body-move-origin=canonical-lowered-view$' "$input_view"; then
            echo "cfg branch bootstrap ir serializer: non-canonical loop body move origin" >&2
            exit 1
        fi
        case "$loop_body_move" in
            *:*)
                body_move_target=${loop_body_move%%:*}
                body_move_value=${loop_body_move#*:}
                ;;
            *)
                echo "cfg branch bootstrap ir serializer: non-canonical loop body move" >&2
                exit 1
                ;;
        esac
        case "$body_move_target" in
            *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
                echo "cfg branch bootstrap ir serializer: non-canonical loop body move target" >&2
                exit 1
                ;;
        esac
        case "$body_move_value" in
            true|false|-[0-9]*|[0-9]*) ;;
            *)
                echo "cfg branch bootstrap ir serializer: non-canonical loop body move value" >&2
                exit 1
                ;;
        esac
    fi

    {
        echo "SSEED-TARGET-V1"
        echo "FUNC_BEGIN|$loop_function|_|_"
        if [ -n "$loop_initial_condition" ]; then
            echo "MOV|$loop_condition|$loop_initial_condition|_"
        fi
        echo "LABEL|$loop_header|_|_"
        echo "JUMP_IF_FALSE|$loop_exit|$loop_condition|_"
        echo "JUMP|$loop_body|_|_"
        echo "LABEL|$loop_body|_|_"
        if [ -n "$body_move_target" ]; then
            echo "MOV|$body_move_target|$body_move_value|_"
        fi
        echo "JUMP|$loop_backedge|_|_"
        echo "LABEL|$loop_exit|_|_"
        if [ -n "$loop_return" ]; then
            echo "RET|$loop_return|_|_"
        fi
        echo "FUNC_END|$loop_function|_|_"
    } >"$output_ir"
    exit 0
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
true_target=$(
    awk '
        /^function / { current=$2 }
        current == "choose" && /^true-edge=/ {
            split($0, parts, "=")
            value = parts[2]
        }
        END { if (value != "") print value }
    ' "$input_view"
)
false_target=$(
    awk '
        /^function / { current=$2 }
        current == "choose" && /^false-edge=/ {
            split($0, parts, "=")
            value = parts[2]
        }
        END { if (value != "") print value }
    ' "$input_view"
)
true_value=$(
    awk -v true_target="$true_target" '
        /^function / { current=$2 }
        /^block / { block=$2 }
        /^return-constant=/ {
            if (current == "choose" && block == true_target) {
                split($0, parts, "=")
                value = parts[2]
            }
        }
        END { if (value != "") print value }
    ' "$input_view"
)
false_value=$(
    awk -v false_target="$false_target" '
        /^function / { current=$2 }
        /^block / { block=$2 }
        /^return-constant=/ {
            if (current == "choose" && block == false_target) {
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

if [ -z "$condition" ] || [ -z "$true_target" ] || [ -z "$false_target" ] || [ -z "$true_value" ] || [ -z "$false_value" ] || [ -z "$main_arg" ]; then
    echo "cfg branch bootstrap ir serializer: missing branch facts" >&2
    exit 1
fi

if ! grep -q '^branch-condition-origin=canonical-mir-terminator$' "$input_view"; then
    echo "cfg branch bootstrap ir serializer: non-canonical branch condition origin" >&2
    exit 1
fi

if ! grep -q '^true-edge-origin=canonical-mir-terminator$' "$input_view"; then
    echo "cfg branch bootstrap ir serializer: non-canonical true edge origin" >&2
    exit 1
fi

if ! grep -q '^false-edge-origin=canonical-mir-terminator$' "$input_view"; then
    echo "cfg branch bootstrap ir serializer: non-canonical false edge origin" >&2
    exit 1
fi

case "$condition" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
        echo "cfg branch bootstrap ir serializer: non-canonical branch condition" >&2
        exit 1
        ;;
esac

for target in "$true_target" "$false_target"; do
    case "$target" in
        *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|"")
            echo "cfg branch bootstrap ir serializer: non-canonical branch target" >&2
            exit 1
            ;;
        bb*) ;;
        *)
            echo "cfg branch bootstrap ir serializer: non-canonical branch target" >&2
            exit 1
            ;;
    esac
done

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
    echo "JUMP_IF_FALSE|$false_target|$condition|_"
    echo "LABEL|$true_target|_|_"
    echo "RET|$true_value|_|_"
    echo "LABEL|$false_target|_|_"
    echo "RET|$false_value|_|_"
    echo "FUNC_END|choose|_|_"
    echo "FUNC_BEGIN|main|_|_"
    echo "ARG|$main_arg|_|_"
    echo "CALL|call_result|choose|1"
    echo "RET|call_result|_|_"
    echo "RET|0|_|_"
    echo "FUNC_END|main|_|_"
} >"$output_ir"
