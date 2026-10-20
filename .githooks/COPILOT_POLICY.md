# Commit Policy - No Copilot Information

## 规则

所有提交到远程仓库（特别是 `main` 分支）的代码**只能**包含以下作者信息：

- **Author**: `shuwenhe <1201220707@pku.edu.cn>`
- **Co-authored-by**: 禁止任何形式的 Copilot Co-authored-by 信息

## 自动保护

本项目使用 Git 钩子在两个层次防止 Copilot 信息进入远程仓库：

### 1. Pre-commit Hook (`.githooks/commit-msg`)
- **触发时机**: 执行 `git commit` 时
- **功能**: 检查提交信息是否包含 `Co-authored-by: Copilot`
- **结果**: 如果检测到，拒绝提交并显示错误信息

```bash
❌ ERROR: Commit message contains Copilot Co-authored-by trailer!
```

### 2. Pre-push Hook (`.githooks/pre-push`)
- **触发时机**: 执行 `git push` 时
- **功能**: 扫描即将推送到 `main` 的所有新提交
- **结果**: 如果检测到任何 Copilot 相关提交，阻止推送

```bash
❌ ERROR: Cannot push commits with Copilot Co-authored-by trailers!
```

## 配置

Git 已配置为使用 `.githooks` 目录：

```bash
git config core.hooksPath
# 输出: .githooks
```

所有开发人员克隆此仓库后，钩子会自动生效。

## 如果意外创建了包含 Copilot 信息的提交

### 方法 1: 如果未推送（只在本地）

使用 `git commit --amend` 编辑提交信息：

```bash
git commit --amend --message "$(git log -1 --format=%B | sed '/^Co-authored-by: Copilot/d')"
```

### 方法 2: 如果已推送（需要强制更新）

使用 git filter-branch 清理历史：

```bash
git filter-branch -f --msg-filter '
sed "/^Co-authored-by: Copilot/d"
' HEAD

git push --force origin main
```

## 验证

检查历史中是否存在 Copilot 信息：

```bash
git log --all --format="%B" | grep -i "copilot"
# 输出: (空) ✓
```

检查本地是否有未推送的 Copilot 提交：

```bash
git log origin/main..HEAD --format="%B" | grep -i "copilot"
# 输出: (空) ✓
```

## 后续措施

- 该策略对所有分支都有效，对 `main` 分支有强制检查
- 所有新提交会自动使用配置的作者信息：`shuwenhe <1201220707@pku.edu.cn>`
- 确保项目历史清晰，仅反映实际的人类贡献者

---

**最后更新**: 2026-10-19  
**执行者**: shuwenhe <1201220707@pku.edu.cn>
