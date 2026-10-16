#!/usr/bin/env python3
"""
Convert S language 'use' statements to 'import' bracket syntax.
Handles module grouping and function call updates.
"""

import os
import re
import sys
from pathlib import Path
from collections import defaultdict

def extract_use_statements(content):
    """Extract all use statements and return them with line numbers."""
    use_pattern = re.compile(r'^use\s+([\w.]+)$', re.MULTILINE)
    matches = []
    for match in use_pattern.finditer(content):
        full_path = match.group(1)
        start = match.start()
        end = match.end()
        matches.append({
            'full_path': full_path,
            'start': start,
            'end': end,
            'match': match.group(0)
        })
    return matches

def parse_module_and_function(full_path):
    """
    Parse a use statement to extract module and function name.
    E.g., 'compile.internal.mir.trace_branch' -> ('compile.internal.mir', 'trace_branch')
    """
    parts = full_path.rsplit('.', 1)
    if len(parts) == 2:
        module, func = parts
        return module, func
    return None, None

def group_use_statements(use_stmts):
    """Group use statements by their module."""
    modules = defaultdict(list)
    func_to_module = {}
    
    for stmt in use_stmts:
        module, func = parse_module_and_function(stmt['full_path'])
        if module and func:
            modules[module].append(func)
            func_to_module[func] = module
    
    return dict(modules), func_to_module

def generate_import_block(modules):
    """Generate an import block from grouped modules."""
    sorted_modules = sorted(modules.keys())
    import_block = "import (\n"
    for module in sorted_modules:
        import_block += f'    "{module}"\n'
    import_block += ")"
    return import_block

def find_use_block(content):
    """Find the range of consecutive use statements at the beginning of the file."""
    lines = content.split('\n')
    
    # Find package line
    package_idx = -1
    first_use_idx = -1
    last_use_idx = -1
    
    for i, line in enumerate(lines):
        if line.startswith('package '):
            package_idx = i
        elif line.startswith('use ') and first_use_idx == -1:
            first_use_idx = i
            last_use_idx = i
        elif line.startswith('use ') and first_use_idx != -1:
            last_use_idx = i
        elif first_use_idx != -1 and last_use_idx != -1 and not line.startswith('use '):
            break
    
    return package_idx, first_use_idx, last_use_idx

def replace_use_statements(content):
    """Replace use statements with import block."""
    use_stmts = extract_use_statements(content)
    if not use_stmts:
        return content, {}
    
    modules, func_to_module = group_use_statements(use_stmts)
    import_block = generate_import_block(modules)
    
    # Find use block range
    package_idx, first_use_idx, last_use_idx = find_use_block(content)
    
    if first_use_idx == -1:
        return content, func_to_module
    
    lines = content.split('\n')
    
    # Replace use statements with import block
    new_lines = lines[:first_use_idx] + [import_block] + lines[last_use_idx + 1:]
    new_content = '\n'.join(new_lines)
    
    return new_content, func_to_module

def update_function_calls(content, func_to_module):
    """Update function calls to include module prefixes."""
    # Sort functions by length (longest first) to avoid partial replacements
    sorted_funcs = sorted(func_to_module.keys(), key=len, reverse=True)
    
    for func in sorted_funcs:
        module = func_to_module[func]
        # Match function calls but not when already prefixed
        pattern = r'\b' + re.escape(func) + r'\s*\('
        replacement = f'{module}.{func}('
        
        def replacer(match):
            # Check if already prefixed
            start = match.start()
            if start > 0 and content[start - 1] == '.':
                return match.group(0)
            return replacement
        
        content = re.sub(pattern, replacer, content)
    
    return content

def process_file(filepath):
    """Process a single S file."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Skip if no use statements
        if not re.search(r'^use ', content, re.MULTILINE):
            return False, "No use statements found"
        
        # Skip if already has import statements
        if re.search(r'^import\s*\(', content, re.MULTILINE):
            return False, "Already uses import syntax"
        
        # Replace use statements
        new_content, func_to_module = replace_use_statements(content)
        if not func_to_module:
            return False, "No valid use statements found"
        
        # Update function calls
        new_content = update_function_calls(new_content, func_to_module)
        
        # Write back
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        
        return True, f"Converted {len(func_to_module)} functions, {len(set(func_to_module.values()))} modules"
    
    except Exception as e:
        return False, f"Error: {str(e)}"

def main():
    s_root = Path('/Users/shuwen/shuwen/s')
    src_dir = s_root / 'src'
    
    # Find all .s files with use statements
    s_files = []
    for s_file in src_dir.rglob('*.s'):
        with open(s_file, 'r', encoding='utf-8', errors='ignore') as f:
            if re.search(r'^use ', f.read(), re.MULTILINE):
                s_files.append(s_file)
    
    print(f"Found {len(s_files)} files to convert")
    
    converted = 0
    skipped = 0
    errors = 0
    
    for i, filepath in enumerate(sorted(s_files), 1):
        rel_path = filepath.relative_to(s_root)
        success, msg = process_file(filepath)
        
        if success:
            converted += 1
            status = "✓"
        elif "No valid" in msg or "No use" in msg or "Already uses" in msg:
            skipped += 1
            status = "⊘"
        else:
            errors += 1
            status = "✗"
        
        print(f"[{i:3d}/{len(s_files)}] {status} {rel_path}: {msg}")
    
    print(f"\n=== Summary ===")
    print(f"Converted: {converted}")
    print(f"Skipped:   {skipped}")
    print(f"Errors:    {errors}")
    print(f"Total:     {len(s_files)}")

if __name__ == '__main__':
    main()
