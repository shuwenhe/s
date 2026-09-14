#!/bin/zsh
# Pure zsh comment removal - no external commands needed

# Function to remove comments from content
remove_all_comments() {
    local content="$1"
    local result=""
    local i=1
    local len=${#content}
    local in_string=0
    local string_char=""
    local in_multiline=0
    
    while (( i <= len )); do
        local c="${content:$((i-1)):1}"
        local cc="${content:$((i-1)):2}"
        local next_c="${content:$i:1}"
        
        # Handle escape sequences
        if [[ $in_string -ne 0 && "$c" == "\\" && "$next_c" != "" ]]; then
            result+="$c$next_c"
            ((i += 2))
            continue
        fi
        
        # Handle string start/end
        if [[ $in_string -eq 0 && ( "$c" == '"' || "$c" == "'" ) ]]; then
            in_string=1
            string_char="$c"
            result+="$c"
            ((i++))
            continue
        fi
        
        if [[ $in_string -ne 0 && "$c" == "$string_char" ]]; then
            in_string=0
            string_char=""
            result+="$c"
            ((i++))
            continue
        fi
        
        # If in string, keep everything
        if [[ $in_string -ne 0 ]]; then
            result+="$c"
            ((i++))
            continue
        fi
        
        # Handle multi-line comments
        if [[ "$cc" == "/*" && $in_multiline -eq 0 ]]; then
            in_multiline=1
            ((i += 2))
            continue
        fi
        
        if [[ "$cc" == "*/" && $in_multiline -ne 0 ]]; then
            in_multiline=0
            ((i += 2))
            continue
        fi
        
        # If in multiline comment, skip
        if [[ $in_multiline -ne 0 ]]; then
            if [[ "$c" == $'\n' ]]; then
                result+=$'\n'
            fi
            ((i++))
            continue
        fi
        
        # Handle single-line comments
        if [[ "$cc" == "//" ]]; then
            # Skip to end of line
            while (( i <= len )); do
                c="${content:$((i-1)):1}"
                if [[ "$c" == $'\n' ]]; then
                    result+=$'\n'
                    ((i++))
                    break
                fi
                ((i++))
            done
            continue
        fi
        
        # Keep everything else
        result+="$c"
        ((i++))
    done
    
    echo "$result"
}

# Function to clean empty lines
clean_empty_lines() {
    local text="$1"
    local lines=("${(@f)text}")  # Split by newline
    local result=""
    local prev_empty=0
    
    for line in "${lines[@]}"; do
        if [[ -z "${line//[[:space:]]}" ]]; then
            if (( ! prev_empty )); then
                result+=$'\n'
                prev_empty=1
            fi
        else
            result+="$line"$'\n'
            prev_empty=0
        fi
    done
    
    # Remove trailing newline
    result="${result%$'\n'}"
    echo "$result"
}

# Main processing
process_s_file() {
    local file="$1"
    
    # Skip if not a regular file
    [[ ! -f "$file" ]] && return 1
    
    # Read file
    local content=$(<"$file")
    
    # Remove comments
    local cleaned=$(remove_all_comments "$content")
    
    # Clean empty lines
    cleaned=$(clean_empty_lines "$cleaned")
    
    # Write back
    print -r -- "$cleaned" > "$file"
    
    return 0
}

# Main loop
cd /Users/feifei/shuwen/s || exit 1

local count=0
local total=0
local dir

for dir in src/cmd/compile src/cmd/s src/runtime; do
    if [[ -d "$dir" ]]; then
        for file in $dir/**/*.s(.); do
            ((total++))
            if process_s_file "$file"; then
                ((count++))
                print "✓ $file"
            else
                print "✗ $file" >&2
            fi
        done
    fi
done

print ""
print "Processed $count/$total files"
