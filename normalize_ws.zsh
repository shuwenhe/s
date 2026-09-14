#!/bin/zsh

# Read file, identify blocks, add spacing
normalize_file_blocks() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    
    local content=$(<"$file")
    local lines=("${(@f)content}")
    local result=()
    
    local -i i=0
    local -i len=${#lines[@]}
    local last_was_decl_closing=0  # Was last non-blank a closing brace of decl?
    
    while (( i < len )); do
        local line="${lines[i]}"
        local trimmed="${line//[[:space:]]/}"
        
        # Completely blank line - skip for now
        if [[ -z "$trimmed" ]]; then
            ((i++))
            continue
        fi
        
        # Check if this line is the start of a declaration
        local is_decl_start=0
        if [[ "$line" =~ ^[[:space:]]*(func|struct|enum)[[:space:]]+ ]]; then
            is_decl_start=1
        fi
        
        # If last was closing and current is start, add blank
        if (( last_was_decl_closing && is_decl_start )); then
            if (( ${#result[@]} > 0 )); then
                local last="${result[-1]}"
                local last_trimmed="${last//[[:space:]]/}"
                if [[ -n "$last_trimmed" ]]; then
                    result+=("")
                fi
            fi
        fi
        
        result+="$line"
        
        # Check if this line contains a closing brace of a declaration
        # (but only if it's not opening and closing on same line like struct foo {})
        if [[ "$trimmed" == "}" ]] || [[ "$line" == *"}"* ]]; then
            if [[ ! "$trimmed" == "{}" ]] && [[ ! "$line" == *"{}"* ]]; then
                last_was_decl_closing=1
            fi
        else
            # Reset if we see other content
            if [[ -n "$trimmed" ]]; then
                last_was_decl_closing=0
            fi
        fi
        
        ((i++))
    done
    
    # Pass 2: Remove multiple blank lines
    local final=()
    local prev_blank=0
    for line in "${result[@]}"; do
        local trimmed="${line//[[:space:]]/}"
        if [[ -z "$trimmed" ]]; then
            if (( ! prev_blank )); then
                final+=("")
                prev_blank=1
            fi
        else
            final+="$line"
            prev_blank=0
        fi
    done
    
    # Remove trailing blanks
    while (( ${#final[@]} > 0 )); do
        local last="${final[-1]}"
        if [[ -z "${last//[[:space:]]/}" ]]; then
            final[-1]=()
        else
            break
        fi
    done
    
    # Write back
    {
        for line in "${final[@]}"; do
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
    if normalize_file_blocks "$file" 2>/dev/null; then
        ((count++))
    fi
done

print "Normalized $count/$total files"
