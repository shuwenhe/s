#!/bin/zsh

normalize_file_improved() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    
    # Read entire file
    local content=$(<"$file")
    local lines=("${(@f)content}")
    
    local result=()
    local -i i=0
    local -i len=${#lines[@]}
    local in_block=0
    local last_decl_end_idx=-1
    
    while (( i < len )); do
        local line="${lines[i]}"
        local trimmed="${line//[[:space:]]/}"
        
        # Skip if line is completely blank
        if [[ -z "$trimmed" ]]; then
            ((i++))
            continue
        fi
        
        # Check if line starts a declaration (func, struct, enum)
        local is_decl=0
        if [[ "$line" =~ ^[[:space:]]*(func|struct|enum)[[:space:]]+ ]]; then
            is_decl=1
        fi
        
        # If we're starting a new declaration and we have previous declarations
        if (( is_decl && last_decl_end_idx >= 0 && ${#result[@]} > 0 )); then
            # Check if we need to add a blank line
            local last_line="${result[-1]}"
            local last_trimmed="${last_line//[[:space:]]/}"
            
            if [[ -n "$last_trimmed" ]]; then
                result+=("")
            fi
        fi
        
        result+="$line"
        
        # If this is a declaration, check if it has a block (struct/enum with {...})
        if (( is_decl )); then
            # Check if line contains opening brace or closing brace
            if [[ "$line" == *"{" ]]; then
                in_block=1
            fi
            
            if [[ "$line" == *"}" ]] && (( in_block )); then
                in_block=0
                last_decl_end_idx=$((${#result[@]} - 1))
            fi
            
            # For func declarations, find the closing brace
            if [[ "$line" =~ ^[[:space:]]*func ]]; then
                # Scan forward for closing brace
                local -i j=$((i + 1))
                while (( j < len )); do
                    local next_line="${lines[j]}"
                    result+="$next_line"
                    
                    if [[ "$next_line" == *"}" && "$next_line" != *"{" ]]; then
                        last_decl_end_idx=$((${#result[@]} - 1))
                        i=$j
                        break
                    fi
                    ((j++))
                done
            fi
        fi
        
        ((i++))
    done
    
    # Second pass: remove multiple consecutive blank lines
    local final_result=()
    local -i prev_blank=0
    for line in "${result[@]}"; do
        local trimmed="${line//[[:space:]]/}"
        if [[ -z "$trimmed" ]]; then
            if (( ! prev_blank )); then
                final_result+=("")
                prev_blank=1
            fi
        else
            final_result+="$line"
            prev_blank=0
        fi
    done
    
    # Remove trailing blank lines
    while (( ${#final_result[@]} > 0 )); do
        local last="${final_result[-1]}"
        local last_trimmed="${last//[[:space:]]/}"
        if [[ -z "$last_trimmed" ]]; then
            final_result[-1]=()
        else
            break
        fi
    done
    
    # Write back
    {
        for line in "${final_result[@]}"; do
            print -r "$line"
        done
    } > "$file"
    
    return 0
}

# Main
cd /Users/feifei/shuwen/s || exit 1

local count=0
local total=0

print "Normalizing whitespace (improved)..."

for file in src/**/*.s; do
    if [[ -f "$file" ]]; then
        ((total++))
        if normalize_file_improved "$file"; then
            ((count++))
        else
            print "✗ $file" >&2
        fi
    fi
done

print "Normalized $count/$total files"
