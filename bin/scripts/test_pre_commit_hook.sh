#!/bin/bash

# Test script for pre-commit hook

echo "Testing pre-commit hook..."
echo ""

# Create a temp directory for testing
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Initialize a git repo
git init --quiet
cp /Users/feifei/shuwen/.git/hooks/pre-commit ./.git/hooks/pre-commit 2>/dev/null
chmod +x ./.git/hooks/pre-commit 2>/dev/null

# Test 1: File with bad syntax should fail
echo "Test 1: Trailing array syntax (should FAIL hook)"
cat > bad_syntax.s << 'EOF'
package main

func test() void {
    var arr = int[]{1, 2, 3}  // BAD: trailing syntax
    var names = string[10]{"a", "b"}  // BAD: trailing syntax
}
EOF

git add bad_syntax.s
if git commit -m "test bad syntax" --quiet 2>&1 | grep -q "ARRAY SYNTAX ERROR"; then
    echo "✓ Hook correctly rejected trailing array syntax"
else
    echo "✗ Hook should have rejected trailing array syntax"
fi

# Test 2: File with good syntax should pass
echo ""
echo "Test 2: Prefix array syntax (should PASS hook)"
git reset --hard --quiet HEAD~1 2>/dev/null
cat > good_syntax.s << 'EOF'
package main

func test() void {
    var arr = []int{1, 2, 3}  // GOOD: prefix syntax
    var names = [10]string{"a", "b"}  // GOOD: prefix syntax
}
EOF

git add good_syntax.s
if git commit -m "test good syntax" --quiet 2>&1; then
    echo "✓ Hook correctly accepted prefix array syntax"
else
    echo "✗ Hook should have accepted prefix array syntax"
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"
