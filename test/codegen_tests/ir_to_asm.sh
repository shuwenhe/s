#!/bin/bash

# IR to x86-64 Assembly Converter for S Language
# Converts SSEED-TARGET-V1 IR format to GNU assembly syntax

IR_FILE="$1"
ASM_FILE="$2"

if [[ -z "$IR_FILE" ]] || [[ -z "$ASM_FILE" ]]; then
    echo "Usage: ir_to_asm.sh <input.ir> <output.s>"
    exit 1
fi

# Create output assembly file
cat > "$ASM_FILE" << 'EOF'
.section .text
.globl main
main:
    # Function prologue
    push %rbp
    mov %rsp, %rbp
    
    # Allocate space for local variables (max 32 bytes for temp vars)
    sub $32, %rsp
    
EOF

# Parse IR line by line
REGISTER_MAP=""  # Maps temp registers to physical registers
RVAR_OFFSET=0    # Offset for spilled variables on stack

# Read IR file and convert instructions
while IFS= read -r line; do
    # Skip header and function markers
    if [[ "$line" == "SSEED-TARGET-V1" ]]; then
        continue
    fi
    if [[ "$line" == FUNC_BEGIN* ]]; then
        FUNC_NAME=$(echo "$line" | cut -d'|' -f2)
        continue
    fi
    if [[ "$line" == FUNC_END* ]]; then
        # Function epilogue
        cat >> "$ASM_FILE" << 'EOF'
    
    # Function epilogue
    mov %rbp, %rsp
    pop %rbp
    ret
EOF
        continue
    fi
    
    # Parse instruction format: INSTR|result|op1|op2
    IFS='|' read -ra PARTS <<< "$line"
    INSTR="${PARTS[0]}"
    RESULT="${PARTS[1]}"
    OP1="${PARTS[2]}"
    OP2="${PARTS[3]}"
    
    case "$INSTR" in
        ADD)
            # ADD: add op1 and op2, store in result
            if [[ "$OP1" == "t"* ]] || [[ "$OP1" =~ ^[0-9]+$ ]]; then
                if [[ "$OP2" == "t"* ]] || [[ "$OP2" =~ ^[0-9]+$ ]]; then
                    cat >> "$ASM_FILE" << EOF
    # ADD $RESULT = $OP1 + $OP2
    mov \$$OP1, %rax
    add \$$OP2, %rax
    # Store result in $RESULT
    mov %rax, -$((RVAR_OFFSET + 8))(%rbp)
EOF
                    RVAR_OFFSET=$((RVAR_OFFSET + 8))
                fi
            fi
            ;;
        SUB)
            # SUB: subtract op2 from op1, store in result
            cat >> "$ASM_FILE" << EOF
    # SUB $RESULT = $OP1 - $OP2
    mov \$$OP1, %rax
    sub \$$OP2, %rax
    mov %rax, -$((RVAR_OFFSET + 8))(%rbp)
EOF
            RVAR_OFFSET=$((RVAR_OFFSET + 8))
            ;;
        MUL)
            # MUL: multiply op1 and op2, store in result
            cat >> "$ASM_FILE" << EOF
    # MUL $RESULT = $OP1 * $OP2
    mov \$$OP1, %rax
    imul \$$OP2, %rax
    mov %rax, -$((RVAR_OFFSET + 8))(%rbp)
EOF
            RVAR_OFFSET=$((RVAR_OFFSET + 8))
            ;;
        RET)
            # RET: return value in result register
            if [[ "$RESULT" == "t"* ]]; then
                cat >> "$ASM_FILE" << EOF
    # RET: return temp var (not yet resolved)
    mov -8(%rbp), %rax
EOF
            else
                cat >> "$ASM_FILE" << EOF
    # RET: return immediate value
    mov \$$RESULT, %rax
EOF
            fi
            ;;
        *)
            # Skip unknown instructions
            echo "# Unknown instruction: $INSTR" >> "$ASM_FILE"
            ;;
    esac
done < "$IR_FILE"

# Ensure file ends properly
if ! grep -q "ret" "$ASM_FILE"; then
    cat >> "$ASM_FILE" << 'EOF'

.section .data
EOF
fi

echo "✓ Converted IR to assembly: $ASM_FILE"
