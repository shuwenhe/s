#!/bin/bash
# 统一 S 语言项目中的指针声明格式
# 从 name* type 改为 type* name
# 用法: bash scripts/unify-pointer-format.sh

set -e

PROJECT_ROOT="/Users/feifei/shuwen/s"
cd "$PROJECT_ROOT"

echo "开始统一指针格式..."
echo "处理范围: $PROJECT_ROOT"
echo ""

# 统计处理前的数量
BEFORE=$(find src -name "*.s" -exec grep -h '^\s*[a-z_][a-z0-9_]*\*\s\+[a-z_][a-z0-9_]*' {} \; | wc -l)
echo "处理前: $BEFORE 处指针声明需要修改"

# 处理所有 .s 文件中的指针声明
# 这个 regex 匹配: name* type → type* name
# 但要排除某些特殊情况（如已是正确格式的）

find src -name "*.s" -type f | while read file; do
    # 创建备份
    cp "$file" "$file.bak"
    
    # 在 struct 字段中：name* type → type* name
    # 匹配：行首空白 + 单词 + * + 空格 + 单词
    sed -i '' -E 's/^([ \t]+)([a-z_][a-z0-9_]*)\*[ \t]+([a-z_][a-z0-9_]*)([ \t]*$)/\1\3* \2\4/g' "$file"
    
    # 在函数参数中：name* type → type* name
    # 匹配：逗号或括号后面的参数声明
    sed -i '' -E 's/\(([a-z_][a-z0-9_]*)\*[ \t]+([a-z_][a-z0-9_]*)/(\2* \1/g' "$file"
    sed -i '' -E 's/,[ \t]*([a-z_][a-z0-9_]*)\*[ \t]+([a-z_][a-z0-9_]*)/,\2* \1/g' "$file"
    
    # 如果文件没有改变，删除备份
    if cmp -s "$file" "$file.bak"; then
        rm "$file.bak"
    else
        echo "已修改: $file"
        rm "$file.bak"
    fi
done

# 统计处理后的数量
AFTER=$(find src -name "*.s" -exec grep -h '^\s*[a-z_][a-z0-9_]*\*\s\+[a-z_][a-z0-9_]*' {} \; | wc -l)
echo ""
echo "处理后: $AFTER 处指针声明仍需修改"
echo "修改数量: $((BEFORE - AFTER))"
echo ""
echo "✓ 统一指针格式完成"
