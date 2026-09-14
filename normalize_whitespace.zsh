#!/bin/zsh

# Normalize whitespace in S source files
# Rules:
# - Remove multiple consecutive blank lines (keep only 1)
# - func/struct/enum must have exactly 1 blank line between them
# - Remove trailing blank lines

normalize_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    
    # Read file into array
    local lines=()
    local -i i=0
    while IFS= read -r line; do
        lines+="$line"
        ((i++))
    done < "$file"
    
    local result=()
    local -i prev_is_blank=0
    local -i prev_is_decl=0
    local line
    
    for line in "${lines[@]}"; do
        # Check if line is blank (only whitespace)
        if [[ -z "${line//[[:space:]]}" ]]; then
            # If previous was also blank, skip this one
            if (( prev_is_blank )); then
                continue
            fi
            # Add blank line
            result+=("")
            prev_is_blank=1
            prev_is_decl=0
        else
            # Non-blank line
            # Check if this is a func, struct, or enum declaration
            local trimmed="${line//^[[:space:]]/}"
            local is_decl=0
            
            if [[ "$trimmed" == func* ]] || [[ "$trimmed" == struct* ]] || [[ "$trimmed" == enum* ]]; then
                is_decl=1
            fi
            
            # If we need spacing between declarations
            if (( prev_is_decl && is_decl )) && (( ! prev_is_blank )); then
                # Add blank line before this declaration
                result+=("")
            fi
            
            result+="$line"
            prev_is_blank=0
            prev_is_decl=$is_decl
        fi
    done
    
    # Remove trailing blank lines
    while (( ${#result[@]} > 0 )); do
        local last="${result[-1]}"
        if [[ -z "${last//[[:space:]]}" ]]; then
            result[-1]=()
        else
            break
        fi
    done
    
    # Write back to file
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

# Process all .s files
for file in src/**/*.s; do
    if [[ -f "$file" ]]; then
        ((total++))
        if normalize_file "$file"; then
            ((count++))
            print "✓ $file"
        else
            print "✗ $file (failed)" >&2
        fi
    fi
done

print ""
print "Normalized $count/$total files"
