#!/bin/bash
# 统一 S 语言项目中的 token 字段名
# 从 type_ 改为 kind

set -e

PROJECT_ROOT="/Users/feifei/shuwen/s"
cd "$PROJECT_ROOT"

echo "开始将 type_ 改为 kind..."
echo "处理范围: $PROJECT_ROOT"
echo ""

# 统计改之前
BEFORE=$(find src -name "*.s" -exec grep -c "type_" {} + | awk '{sum+=$1} END {print sum}')
echo "改之前: 约 $BEFORE 处引用 type_"

# 使用 sed 在所有 .s 文件中替换
find src -name "*.s" -type f | while read file; do
    # 跳过测试 fixture 文件
    if [[ "$file" == *"fixtures"* ]]; then
        continue
    fi
    
    # 替换所有 .type_ → .kind
    sed -i '' 's/\.type_/.kind/g' "$file"
    
    # 替换 struct 定义中的 type_
    sed -i '' 's/int\* type_/int* kind/g' "$file"
    sed -i '' 's/int\*type_/int* kind/g' "$file"
done

# 统计改之后
AFTER=$(find src -name "*.s" -exec grep -c "type_" {} + | awk '{sum+=$1} END {print sum}')
echo "改之后: 约 $AFTER 处仍有 type_"
echo "已改动: 约 $((BEFORE - AFTER)) 处"
echo ""

# 统计 kind 的使用
KIND_COUNT=$(find src -name "*.s" -exec grep -c "\.kind\|int\* kind" {} + | awk '{sum+=$1} END {print sum}')
echo "新增: 约 $KIND_COUNT 处使用 kind"
echo ""
echo "✓ 改动完成"
echo ""
echo "需要验证的地方:"
echo "1. 检查是否有遗漏的 type_ 引用"
echo "2. 编译测试: make seed-compiler-bin"
echo "3. 运行词法分析器测试"
