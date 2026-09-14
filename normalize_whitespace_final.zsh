#!/bin/zsh

# Simple and reliable whitespace normalization
normalize_file_simple() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    
    local content=$(<"$file")
    local lines=("${(@f)content}")
    
    local result=()
    local -i i=0
    local -i len=${#lines[@]}
    
    # First pass: collect all lines, skip multiple blanks, add blanks between declarations
    while (( i < len )); do
        local line="${lines[i]}"
        local trimmed="${line//[[:space:]]/}"
        
        # If blank line
        if [[ -z "$trimmed" ]]; then
            # Check if previous line in result is also blank
            if (( ${#result[@]} > 0 )); then
                local last="${result[-1]}"
                local last_trimmed="${last//[[:space:]]/}"
                
                # Only add blank if previous isn't blank
                if [[ -n "$last_trimmed" ]]; then
                    result+=("")
                fi
            fi
            ((i++))
            continue
        fi
        
        # Non-blank line - check if we need spacing
        if (( ${#result[@]} > 0 )); then
            local last_non_empty_idx=-1
            local -i j=$((${#result[@]} - 1))
            
            # Find last non-empty line
            while (( j >= 0 )); do
                local candidate="${result[j]}"
                local cand_trimmed="${candidate//[[:space:]]/}"
                if [[ -n "$cand_trimmed" ]]; then
                    last_non_empty_idx=$j
                    break
                fi
                ((j--))
            done
            
            if (( last_non_empty_idx >= 0 )); then
                local last_non_empty="${result[last_non_empty_idx]}"
                
                # Check if both current and last are declarations
                local curr_is_decl=0
                local last_is_decl=0
                
                if [[ "$line" =~ ^[[:space:]]*(func|struct|enum)[[:space:]]+ ]]; then
                    curr_is_decl=1
                fi
                
                if [[ "$last_non_empty" =~ ^[[:space:]]*(func|struct|enum)[[:space:]]+ ]]; then
                    last_is_decl=1
                elif [[ "$last_non_empty" == "}" ]]; then
                    # Closing brace might be end of func/struct/enum
                    last_is_decl=1
                fi
                
                # Add blank line if we have two declarations and no blank between
                if (( curr_is_decl && last_is_decl )); then
                    local last_idx=$((${#result[@]} - 1))
                    if (( last_idx >= last_non_empty_idx + 1 )); then
                        # There's already spacing
                        :
                    else
                        # No spacing, add one
                        result+=("")
                    fi
                fi
            fi
        fi
        
        result+="$line"
        ((i++))
    done
    
    # Remove trailing blanks
    while (( ${#result[@]} > 0 )); do
        local last="${result[-1]}"
        local last_trimmed="${last//[[:space:]]/}"
        if [[ -z "$last_trimmed" ]]; then
            result[-1]=()
        else
            break
        fi
    done
    
    # Write back
    {
        for line in "${result[@]}"; do
            print -r "$line"
        done
    } > "$file"
    
    return 0
}

# Main
cd /Users/feifei/shuwen/s || exit 1

local count=0
local total=0

print "Normalizing whitespace in S files..."

for file in src/**/*.s(.); do
    ((total++))
    if normalize_file_simple "$file" 2>/dev/null; then
        ((count++))
    fi
done

print "Normalized $count/$total files"
