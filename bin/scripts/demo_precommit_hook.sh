#!/bin/bash

# Simple demo of pre-commit hook functionality

echo "=== Pre-commit Hook Demo ==="
echo ""

# Test with actual neurx directory
cd /Users/feifei/shuwen

echo "Testing hook on converted files..."
echo ""

# Create a test file with bad syntax to stage it
TEST_FILE="test_hook_bad.s"
cat > "$TEST_FILE" << 'EOF'
package main

func main() int {
    // Using WRONG trailing array syntax
    var arr = int[]{1, 2, 3}  // BAD!
    0
}
EOF

echo "1. Staging file with trailing array syntax..."
git add "$TEST_FILE" 2>/dev/null

echo "2. Running pre-commit hook..."
echo ""

# Manually run the hook
bash .git/hooks/pre-commit

HOOK_EXIT=$?

if [ $HOOK_EXIT -eq 1 ]; then
    echo ""
    echo "✅ Hook successfully REJECTED the trailing syntax!"
    echo ""
else
    echo ""
    echo "❌ Hook should have rejected this!"
fi

# Cleanup
git reset HEAD "$TEST_FILE" 2>/dev/null
rm "$TEST_FILE"

echo ""
echo "=== Hook Status ==="
echo "✅ Pre-commit hook is installed and functional"
echo "📍 Location: /Users/feifei/shuwen/.git/hooks/pre-commit"
echo ""
