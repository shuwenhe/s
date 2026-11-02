#!/usr/bin/env python3
"""
Generate arithmetic block tests for performance benchmarking.
Creates S programs with varying numbers of arithmetic operations to test validator performance.
"""

import sys
import os

def generate_arithmetic_test(num_blocks: int) -> str:
    """Generate an S program with num_blocks arithmetic operations."""
    
    code = '''package main

fn add_sequence() int {
    x := 1
'''
    
    # Generate arithmetic operations
    for i in range(num_blocks):
        code += f"    x = x + {i}\n"
    
    code += '''    return x
}

fn main() {
    result := add_sequence()
    return
}
'''
    
    return code

def main():
    if len(sys.argv) < 2:
        print("Usage: generate_arithmetic_test.py <num_blocks> [output_file]")
        sys.exit(1)
    
    try:
        num_blocks = int(sys.argv[1])
    except ValueError:
        print(f"Error: num_blocks must be an integer, got {sys.argv[1]}")
        sys.exit(1)
    
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    code = generate_arithmetic_test(num_blocks)
    
    if output_file:
        with open(output_file, 'w') as f:
            f.write(code)
        print(f"Generated {num_blocks} arithmetic blocks to {output_file}")
    else:
        print(code)

if __name__ == '__main__':
    main()
