#!/bin/bash
# Replace all 'func ' with 'fn ' in S language files
# This aligns with S language's modern AI-native positioning

set -e

WORKSPACE="/Users/feifei/shuwen/train/s"
cd "$WORKSPACE"

echo "🔄 Starting replacement of 'func' -> 'fn' in S language files..."
echo "📁 Workspace: $WORKSPACE"
echo ""

# Count total files that will be processed
TOTAL_FILES=$(find . -name "*.s" -type f | wc -l)
echo "📊 Total .s files found: $TOTAL_FILES"

# Count occurrences of 'func '
TOTAL_OCCURRENCES=$(grep -r "^func " --include="*.s" . 2>/dev/null | wc -l)
echo "🎯 Total 'func ' declarations to replace: $TOTAL_OCCURRENCES"
echo ""

# Perform the replacement
echo "⚙️  Processing..."

find . -name "*.s" -type f -exec sed -i 's/^func /fn /g' {} \;

# Count replacements
NEW_OCCURRENCES=$(grep -r "^fn " --include="*.s" . 2>/dev/null | wc -l)
echo ""
echo "✅ Replacement complete!"
echo "   Original 'fn ' declarations: $NEW_OCCURRENCES"
echo ""

# Verify
REMAINING_FUNC=$(grep -r "^func " --include="*.s" . 2>/dev/null | wc -l || true)
if [ "$REMAINING_FUNC" -eq 0 ]; then
    echo "🎉 SUCCESS: All 'func' keywords have been replaced with 'fn'"
else
    echo "⚠️  WARNING: $REMAINING_FUNC 'func' declarations remain"
fi

# Show some examples
echo ""
echo "📝 Sample of replaced declarations:"
grep -r "^fn " --include="*.s" . 2>/dev/null | head -10 | cut -d: -f2- | sed 's/^/   /'

echo ""
echo "✨ Replacement script completed successfully!"
