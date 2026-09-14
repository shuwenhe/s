#!/bin/bash
# Remove all comments from S source files
# Handles both // single-line and /* */ multi-line comments

process_file() {
    local file="$1"
    local tmpfile="${file}.tmp"
    
    # Use awk to remove comments while preserving strings
    awk '
    BEGIN { in_string = 0; in_multiline = 0 }
    {
        result = ""
        i = 1
        while (i <= length($0)) {
            c = substr($0, i, 1)
            cc = substr($0, i, 2)
            
            # Handle strings
            if ((c == "\"" || c == "'"'"'") && in_string == 0 && in_multiline == 0) {
                in_string = c
                result = result c
            } else if (c == in_string && in_string != 0) {
                in_string = 0
                result = result c
            } else if (in_string != 0) {
                result = result c
            } 
            # Handle multi-line comments
            else if (cc == "/*" && in_multiline == 0) {
                in_multiline = 1
                i = i + 1
            } else if (cc == "*/" && in_multiline == 1) {
                in_multiline = 0
                i = i + 1
            } else if (in_multiline == 1) {
                # Skip
            }
            # Handle single-line comments
            else if (cc == "//" && in_multiline == 0) {
                # Skip rest of line
                break
            } else {
                result = result c
            }
            i = i + 1
        }
        if (in_multiline == 0) {
            # Remove trailing whitespace
            gsub(/[[:space:]]+$/, "", result)
            if (result != "") print result
        }
    }
    END { }
    ' "$file" > "$tmpfile"
    
    mv "$tmpfile" "$file"
}

cd /Users/feifei/shuwen/s
count=0

# Process all .s files
while IFS= read -r -d '' file; do
    process_file "$file"
    ((count++))
    echo "Processed: $file"
done < <(find src -name "*.s" -print0 | sort -z)

echo "Total files processed: $count"
