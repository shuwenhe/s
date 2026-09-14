#!/bin/zsh

normalize_file_precise() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    
    # Read entire file
    local content=$(<"$file")
    local lines=("${(@f)content}")  # Split into lines
    
    local result=()
    local -i i=0
    local -i len=${#lines[@]}
    
    while (( i < len )); do
        local line="${lines[i]}"
        local trimmed="${line//[[:space:]]/}"
        
        # Skip if line is completely blank
        if [[ -z "$trimmed" ]]; then
            ((i++))
            continue
        fi
        
        # Determine what kind of declaration this is
        local curr_kind=""
        if [[ "$line" =~ ^[[:space:]]*func[[:space:]]+ ]]; then
            curr_kind="func"
        elif [[ "$line" =~ ^[[:space:]]*struct[[:space:]]+ ]]; then
            curr_kind="struct"
        elif [[ "$line" =~ ^[[:space:]]*enum[[:space:]]+ ]]; then
            curr_kind="enum"
        fi
        
        # Check if previous item in result needs space
        if [[ -n "$curr_kind" ]] && (( ${#result[@]} > 0 )); then
            local last_idx=$((${#result[@]} - 1))
            local last_line="${result[last_idx]}"
            local last_trimmed="${last_line//[[:space:]]/}"
            
            # If last line is not blank, we need to add spacing
            if [[ -n "$last_trimmed" ]]; then
                local prev_kind=""
                if [[ "$last_line" =~ ^[[:space:]]*func[[:space:]]+ ]]; then
                    prev_kind="func"
                elif [[ "$last_line" =~ ^[[:space:]]*struct[[:space:]]+ ]]; then
                    prev_kind="struct"
                elif [[ "$last_line" =~ ^[[:space:]]*enum[[:space:]]+ ]]; then
                    prev_kind="enum"
                fi
                
                # If previous was also a declaration, add blank line
                if [[ -n "$prev_kind" ]]; then
                    result+=("")
                fi
            fi
        fi
        
        result+="$line"
        ((i++))
    done
    
    # Remove multiple consecutive blank lines
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

# Main execution
cd /Users/feifei/shuwen/s || exit 1

local count=0
local total=0

print "Normalizing whitespace in S files (precise mode)..."

for file in src/**/*.s; do
    if [[ -f "$file" ]]; then
        ((total++))
        if normalize_file_precise "$file"; then
            ((count++))
            # print "✓ $file"
        else
            print "✗ $file" >&2
        fi
    fi
done

print "Normalized $count/$total files"
