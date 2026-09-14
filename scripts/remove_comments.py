#!/usr/bin/env python3
"""
Remove all comments from S language source files.
Handles both // single-line and /* */ multi-line comments.
"""

import re
import os
import sys
from pathlib import Path

def remove_comments(content):
    """Remove comments from S source code."""
    # Track if we're in a string to avoid removing comment-like symbols in strings
    result = []
    i = 0
    
    while i < len(content):
        # Handle string literals
        if content[i] in ('"', "'"):
            quote = content[i]
            result.append(content[i])
            i += 1
            while i < len(content):
                if content[i] == '\\' and i + 1 < len(content):
                    result.append(content[i:i+2])
                    i += 2
                elif content[i] == quote:
                    result.append(content[i])
                    i += 1
                    break
                else:
                    result.append(content[i])
                    i += 1
        # Handle single-line comments
        elif i + 1 < len(content) and content[i:i+2] == '//':
            # Skip until end of line
            while i < len(content) and content[i] != '\n':
                i += 1
            # Preserve the newline
            if i < len(content) and content[i] == '\n':
                result.append('\n')
                i += 1
        # Handle multi-line comments
        elif i + 1 < len(content) and content[i:i+2] == '/*':
            # Skip until */
            i += 2
            while i + 1 < len(content):
                if content[i:i+2] == '*/':
                    i += 2
                    break
                # Preserve newlines for line counting
                if content[i] == '\n':
                    result.append('\n')
                i += 1
        else:
            result.append(content[i])
            i += 1
    
    return ''.join(result)

def clean_empty_lines(content):
    """Remove lines that are empty or only contain whitespace."""
    lines = content.split('\n')
    cleaned = []
    for line in lines:
        if line.strip():  # Keep non-empty lines
            cleaned.append(line)
        elif not cleaned or cleaned[-1]:  # Keep blank lines between content, but not consecutive blanks
            cleaned.append('')
    
    # Remove trailing empty lines
    while cleaned and not cleaned[-1]:
        cleaned.pop()
    
    return '\n'.join(cleaned)

def process_file(filepath):
    """Process a single S source file."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Remove comments
        cleaned = remove_comments(content)
        
        # Clean up empty lines
        cleaned = clean_empty_lines(cleaned)
        
        # Write back
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(cleaned)
        
        return True
    except Exception as e:
        print(f"Error processing {filepath}: {e}", file=sys.stderr)
        return False

def main():
    """Main entry point."""
    project_root = Path('/Users/feifei/shuwen/s')
    s_files = list(project_root.glob('src/**/*.s'))
    
    print(f"Found {len(s_files)} S source files")
    
    success_count = 0
    for s_file in sorted(s_files):
        if process_file(s_file):
            success_count += 1
            print(f"✓ {s_file.relative_to(project_root)}")
        else:
            print(f"✗ {s_file.relative_to(project_root)}")
    
    print(f"\nProcessed {success_count}/{len(s_files)} files successfully")

if __name__ == '__main__':
    main()
