#!/bin/zsh
# Remove comments from S language files using pure zsh

# Function to remove comments from a string
remove_comments() {
    local input="$1"
    local output=""
    local in_string=false
    local string_char=""
    local i=0
    local len=${#input}
    
    while (( i < len )); do
        local char="${input:$i:1}"
        local next_char="${input:$((i+1)):1}"
        
        # Handle string literals
        if [[ "$char" == '"' || "$char" == "'" ]] && [[ $in_string == false ]]; then
            in_string=true
            string_char="$char"
            output+="$char"
            ((i++))
        elif [[ "$char" == "$string_char" ]] && [[ $in_string == true ]]; then
            in_string=false
            output+="$char"
            ((i++))
        elif [[ $in_string == true ]]; then
            output+="$char"
            ((i++))
        # Handle single-line comments
        elif [[ "$char$next_char" == "//" ]]; then
            # Skip to end of line
            while (( i < len )); do
                char="${input:$i:1}"
                if [[ "$char" == $'\n' ]]; then
                    output+=$'\n'
                    ((i++))
                    break
                fi
                ((i++))
            done
        # Handle multi-line comments
        elif [[ "$char$next_char" == "/*" ]]; then
            ((i += 2))
            # Skip until */
            while (( i + 1 < len )); do
                char="${input:$i:1}"
                next_char="${input:$((i+1)):1}"
                if [[ "$char$next_char" == "*/" ]]; then
                    ((i += 2))
                    break
                fi
                if [[ "$char" == $'\n' ]]; then
                    output+=$'\n'
                fi
                ((i++))
            done
        else
            output+="$char"
            ((i++))
        fi
    done
    
    echo "$output"
}

# Main loop
PROJECT_ROOT="/Users/feifei/shuwen/s"
count=0
total=0

for file in $(find "$PROJECT_ROOT/src" -name "*.s" -type f | sort); do
    ((total++))
    
    # Read file content
    content=$(<"$file")
    
    # Remove comments
    cleaned=$(remove_comments "$content")
    
    # Remove empty lines and write back
    echo "$cleaned" | grep -v '^[[:space:]]*$' > "$file.tmp"
    mv "$file.tmp" "$file"
    
    ((count++))
    echo "✓ $file"
done

echo ""
echo "Processed $count/$total files"
