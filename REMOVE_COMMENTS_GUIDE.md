# 去除 S 项目所有注释的完整指南

## 背景
S 项目包含超过 900 个 .s 源文件，需要移除所有注释（// 和 /* */ 形式）。

## 快速执行方法

### 方法 1: 使用提供的脚本（推荐）

```bash
cd /Users/feifei/shuwen/s

# 使用 bash 脚本
bash remove_all_comments.sh

# 或使用 zsh 脚本
zsh scripts/remove_comments.sh

# 或使用 Python
python3 scripts/remove_comments.py
```

## 脚本说明

### remove_all_comments.sh (Bash)
- 使用 awk 处理每个文件
- 正确处理字符串中的 // 和 /*
- 移除单行和多行注释
- 移除空行和尾部空白

### scripts/remove_comments.py (Python)
- 完全用 Python 编写
- 更可靠的字符串和转义处理
- 逐行处理
- 最安全的选项

### scripts/remove_comments.sh (Zsh)
- 使用 zsh 内置功能
- 处理复杂的字符串转义
- 需要较长的执行时间

## 手动验证

处理完成后，验证注释已被移除：

```bash
# 检查是否还有注释
grep -r "\/\/" src/cmd/compile/ | head -20
grep -r "\/\*" src/cmd/compile/ | head -20

# 检查文件数量
find src -name "*.s" -type f | wc -l  # 应该还是相同数量的文件
```

## 恢复备份

如果需要恢复，使用 git：

```bash
git checkout src/  # 恢复所有文件
```

## 警告

- 此操作不可逆（除非使用 git 恢复）
- 某些注释可能包含重要信息
- 建议在提交前仔细审查
- 某些编译器指令注释（如果存在）也会被移除

## 注释统计

在处理前，可以统计注释数量：

```bash
# 统计 // 注释行数
grep -r "\/\/" src/ | wc -l

# 统计 /* */ 块
grep -r "\/\*" src/ | wc -l
```

## 常见问题

Q: 脚本无法运行？
A: 确保文件有执行权限：`chmod +x remove_all_comments.sh`

Q: 字符串中的 // 被移除了？
A: 脚本应该正确处理这个。如果出现问题，请报告具体文件。

Q: 需要保留某些注释？
A: 可以编辑脚本，添加保留模式（如 // FIXME: 保留）
