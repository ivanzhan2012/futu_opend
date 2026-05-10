#!/bin/bash
# 安装 git pre-commit hook
# 使用方式: bash .github/install-hooks.sh

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
    echo "[ERROR] 请在 git 仓库根目录下运行此脚本"
    exit 1
fi

HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"

cat > "$HOOK_PATH" << 'HOOK_EOF'
#!/bin/bash
# pre-commit hook: 使用 gitleaks 扫描本次提交的敏感信息

if ! command -v gitleaks &>/dev/null; then
    echo ""
    echo "⚠️  [安全警告] gitleaks 未安装，跳过敏感信息扫描"
    echo "   安装方式: https://github.com/gitleaks/gitleaks#installing"
    echo "   或运行: bash .github/install-hooks.sh"
    echo ""
    exit 0
fi

echo "[pre-commit] 运行 gitleaks 扫描..."

gitleaks protect \
    --config "$(git rev-parse --show-toplevel)/.gitleaks.toml" \
    --staged \
    --redact \
    --verbose

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ [pre-commit] gitleaks 检测到敏感信息泄露，提交被阻止！"
    echo "   请检查上方输出，清除敏感信息后再提交。"
    echo "   如确认为误报，可在 .gitleaks.toml 中添加排除规则。"
    echo ""
    exit 1
fi

echo "✅ [pre-commit] 未发现敏感信息，提交通过"
HOOK_EOF

chmod +x "$HOOK_PATH"
echo "✅ pre-commit hook 已安装到: $HOOK_PATH"
